import Darwin
import Foundation
import HakenCore
import OSLog

final class HakenIPCServer {
  enum ServerError: Error {
    case socketPathTooLong
    case unsafeExistingSocket
    case systemCall(String, Int32)
  }

  private let socketURL: URL
  private let handler: HakenCLIRequestHandler
  private let queue = DispatchQueue(label: "com.haken.ipc", qos: .userInitiated)
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.haken.app", category: "ipc")
  private var listener: Int32 = -1
  private var source: DispatchSourceRead?

  init(socketURL: URL = HakenIPC.defaultSocketURL(), handler: HakenCLIRequestHandler) {
    self.socketURL = socketURL
    self.handler = handler
  }

  deinit { stop() }

  func start() throws {
    let directory = socketURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    guard chmod(directory.path, 0o700) == 0 else {
      throw ServerError.systemCall("chmod", errno)
    }
    try removeStaleSocketIfSafe()

    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw ServerError.systemCall("socket", errno) }
    do {
      var address = try socketAddress(path: socketURL.path)
      let addressLength = socklen_t(address.sun_len)
      let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.bind(descriptor, $0, addressLength)
        }
      }
      guard result == 0 else { throw ServerError.systemCall("bind", errno) }
      guard chmod(socketURL.path, 0o600) == 0 else {
        throw ServerError.systemCall("chmod", errno)
      }
      guard Darwin.listen(descriptor, 16) == 0 else {
        throw ServerError.systemCall("listen", errno)
      }
      guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
        throw ServerError.systemCall("fcntl", errno)
      }
    } catch {
      Darwin.close(descriptor)
      throw error
    }

    listener = descriptor
    let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
    source.setEventHandler { [weak self] in self?.acceptConnections() }
    source.resume()
    self.source = source
    logger.info("CLI IPC server started")
  }

  func stop() {
    source?.cancel()
    source = nil
    if listener >= 0 {
      Darwin.close(listener)
      listener = -1
    }
    if FileManager.default.fileExists(atPath: socketURL.path) {
      _ = unlink(socketURL.path)
    }
  }

  private func acceptConnections() {
    while listener >= 0 {
      let connection = Darwin.accept(listener, nil, nil)
      if connection < 0 {
        if errno == EINTR { continue }
        if errno == EAGAIN || errno == EWOULDBLOCK { return }
        logger.error("IPC accept failed errno=\(errno, privacy: .public)")
        return
      }
      _ = fcntl(connection, F_SETFL, 0)
      queue.async { [weak self] in self?.handle(connection) }
    }
  }

  private func handle(_ connection: Int32) {
    var noSigPipe: Int32 = 1
    _ = setsockopt(
      connection, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
      socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    _ = setsockopt(
      connection, SOL_SOCKET, SO_RCVTIMEO, &timeout,
      socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(
      connection, SOL_SOCKET, SO_SNDTIMEO, &timeout,
      socklen_t(MemoryLayout<timeval>.size))

    var peerUser = uid_t.max
    var peerGroup = gid_t.max
    guard getpeereid(connection, &peerUser, &peerGroup) == 0, peerUser == geteuid() else {
      logger.error("Rejected CLI IPC connection from another user")
      Darwin.close(connection)
      return
    }

    do {
      let data = try HakenIPCFrame.read(from: connection)
      let request = try JSONDecoder().decode(HakenCLIRequest.self, from: data)
      DispatchQueue.main.async { [weak self] in
        self?.handler.handle(request) { response in
          self?.queue.async {
            defer { Darwin.close(connection) }
            do {
              let encoder = JSONEncoder()
              encoder.outputFormatting = [.sortedKeys]
              try HakenIPCFrame.write(encoder.encode(response), to: connection)
            } catch {
              self?.logger.error("IPC response failed")
            }
          }
        }
      }
    } catch {
      logger.error("IPC request failed: \(String(describing: error), privacy: .public)")
      Darwin.close(connection)
    }
  }

  private func removeStaleSocketIfSafe() throws {
    var info = stat()
    guard lstat(socketURL.path, &info) == 0 else {
      if errno == ENOENT { return }
      throw ServerError.systemCall("lstat", errno)
    }
    guard info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFSOCK else {
      throw ServerError.unsafeExistingSocket
    }
    if canConnect(to: socketURL.path) { throw ServerError.systemCall("connect", EADDRINUSE) }
    guard unlink(socketURL.path) == 0 else { throw ServerError.systemCall("unlink", errno) }
  }

  private func canConnect(to path: String) -> Bool {
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return false }
    defer { Darwin.close(descriptor) }
    guard var address = try? socketAddress(path: path) else { return false }
    let addressLength = socklen_t(address.sun_len)
    return withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, addressLength) == 0
      }
    }
  }

  private func socketAddress(path: String) throws -> sockaddr_un {
    let pathBytes = Array(path.utf8CString)
    var address = sockaddr_un()
    guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
      throw ServerError.socketPathTooLong
    }
    address.sun_family = sa_family_t(AF_UNIX)
    let length = MemoryLayout<sa_family_t>.size + pathBytes.count
    address.sun_len = UInt8(length)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
        _ = pathBytes.withUnsafeBufferPointer { source in
          memcpy(destination, source.baseAddress, pathBytes.count)
        }
      }
    }
    return address
  }
}
