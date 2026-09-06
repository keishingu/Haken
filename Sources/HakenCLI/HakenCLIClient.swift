import Darwin
import Foundation
import HakenCore

enum HakenCLIClientError: Error {
  case appNotFound
  case appUnavailable
  case invalidResponse
  case responseUnavailable(Error)
  case socketPathTooLong
  case transport(Error)
}

struct HakenCLIClient {
  let socketURL: URL

  init(socketURL: URL = HakenIPC.defaultSocketURL()) {
    self.socketURL = socketURL
  }

  func send(
    _ request: HakenCLIRequest, launchApp: Bool, timeoutMilliseconds: Int
  ) throws -> HakenCLIResponse {
    let timeout = max(100, min(timeoutMilliseconds, 10_000))
    if let response = try tryExchange(request, timeoutMilliseconds: timeout) { return response }
    guard launchApp else { throw HakenCLIClientError.appUnavailable }
    try launchHaken()
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(timeout))
    repeat {
      Thread.sleep(forTimeInterval: 0.02)
      if let response = try tryExchange(request, timeoutMilliseconds: timeout) { return response }
    } while ContinuousClock.now < deadline
    throw HakenCLIClientError.appUnavailable
  }

  private func tryExchange(
    _ request: HakenCLIRequest, timeoutMilliseconds: Int
  ) throws -> HakenCLIResponse? {
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      throw HakenCLIClientError.transport(HakenIPCError.connectionFailed(errno))
    }
    defer { Darwin.close(descriptor) }
    var noSigPipe: Int32 = 1
    _ = setsockopt(
      descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
      socklen_t(MemoryLayout<Int32>.size))
    var address = try socketAddress(path: socketURL.path)
    let addressLength = socklen_t(address.sun_len)
    let connected = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, addressLength) == 0
      }
    }
    guard connected else {
      if errno == ENOENT || errno == ECONNREFUSED { return nil }
      throw HakenCLIClientError.transport(HakenIPCError.connectionFailed(errno))
    }

    var timeout = timeval(
      tv_sec: timeoutMilliseconds / 1_000,
      tv_usec: Int32(timeoutMilliseconds % 1_000) * 1_000)
    _ = setsockopt(
      descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout,
      socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(
      descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout,
      socklen_t(MemoryLayout<timeval>.size))
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try HakenIPCFrame.write(encoder.encode(request), to: descriptor)
      return try JSONDecoder().decode(
        HakenCLIResponse.self, from: HakenIPCFrame.read(from: descriptor))
    } catch {
      throw HakenCLIClientError.responseUnavailable(error)
    }
  }

  private func launchHaken() throws {
    guard let appURL = hakenAppURL() else { throw HakenCLIClientError.appNotFound }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [
      "-g", "-j", appURL.path, "--args", "--haken-cli-background",
    ]
    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { throw HakenCLIClientError.appUnavailable }
    } catch {
      throw HakenCLIClientError.transport(error)
    }
  }

  private func hakenAppURL() -> URL? {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    let result = buffer.withUnsafeMutableBufferPointer {
      _NSGetExecutablePath($0.baseAddress, &size)
    }
    let executableURL =
      result == 0
      ? URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
      : URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    var candidate = executableURL
    while candidate.path != "/" {
      if candidate.pathExtension == "app" { return candidate }
      candidate.deleteLastPathComponent()
    }
    for url in [
      URL(fileURLWithPath: "/Applications/Haken.app"),
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Haken.app"),
    ] where FileManager.default.fileExists(atPath: url.path) {
      return url
    }
    return nil
  }

  private func socketAddress(path: String) throws -> sockaddr_un {
    let pathBytes = Array(path.utf8CString)
    var address = sockaddr_un()
    guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
      throw HakenCLIClientError.socketPathTooLong
    }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sa_family_t>.size + pathBytes.count)
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
