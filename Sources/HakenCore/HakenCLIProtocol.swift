import Darwin
import Foundation

public enum HakenJSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([HakenJSONValue])
  case object([String: HakenJSONValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([HakenJSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: HakenJSONValue].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  public var intValue: Int? {
    guard case .int(let value) = self else { return nil }
    return value
  }

  public var boolValue: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }

  public var arrayValue: [HakenJSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  public var objectValue: [String: HakenJSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }
}

public struct HakenCLIRequest: Codable, Equatable, Sendable {
  public static let protocolVersion = 1

  public var protocolVersion: Int
  public var requestId: UUID
  public var method: String
  public var parameters: [String: HakenJSONValue]
  public var dryRun: Bool
  public var confirmed: Bool

  public init(
    requestId: UUID = UUID(), method: String,
    parameters: [String: HakenJSONValue] = [:], dryRun: Bool = false,
    confirmed: Bool = false
  ) {
    self.protocolVersion = Self.protocolVersion
    self.requestId = requestId
    self.method = method
    self.parameters = parameters
    self.dryRun = dryRun
    self.confirmed = confirmed
  }
}

public struct HakenCLIErrorPayload: Codable, Equatable, Sendable {
  public var code: String
  public var message: String
  public var retryable: Bool
  public var hint: String?
  public var details: HakenJSONValue?
  public var exitCode: Int32

  public init(
    code: String, message: String, retryable: Bool = false, hint: String? = nil,
    details: HakenJSONValue? = nil, exitCode: Int32
  ) {
    self.code = code
    self.message = message
    self.retryable = retryable
    self.hint = hint
    self.details = details
    self.exitCode = exitCode
  }
}

public struct HakenCLIResponseMeta: Codable, Equatable, Sendable {
  public var requestId: UUID
  public var cliVersion: String?
  public var appVersion: String
  public var durationMs: Int

  public init(
    requestId: UUID, cliVersion: String? = nil, appVersion: String,
    durationMs: Int
  ) {
    self.requestId = requestId
    self.cliVersion = cliVersion
    self.appVersion = appVersion
    self.durationMs = durationMs
  }
}

public struct HakenCLIResponse: Codable, Equatable, Sendable {
  public static let apiVersion = "haken.cli/v1"

  public var apiVersion: String
  public var ok: Bool
  public var command: String
  public var data: HakenJSONValue?
  public var error: HakenCLIErrorPayload?
  public var meta: HakenCLIResponseMeta

  public init(
    ok: Bool, command: String, data: HakenJSONValue? = nil,
    error: HakenCLIErrorPayload? = nil, meta: HakenCLIResponseMeta
  ) {
    self.apiVersion = Self.apiVersion
    self.ok = ok
    self.command = command
    self.data = data
    self.error = error
    self.meta = meta
  }
}

public enum HakenIPC {
  public static let maximumFrameSize = 4 * 1_024 * 1_024

  public static func defaultSocketURL(fileManager: FileManager = .default) -> URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Haken", isDirectory: true)
      .appendingPathComponent("run", isDirectory: true)
      .appendingPathComponent("haken.sock", isDirectory: false)
  }
}

public enum HakenIPCError: Error, Equatable, Sendable {
  case connectionFailed(Int32)
  case endOfStream
  case frameTooLarge(Int)
  case invalidFrame
  case readFailed(Int32)
  case writeFailed(Int32)
}

public enum HakenIPCFrame {
  public static func read(from descriptor: Int32) throws -> Data {
    let header = try readExactly(4, from: descriptor)
    let length = header.withUnsafeBytes { bytes in
      bytes.loadUnaligned(as: UInt32.self).bigEndian
    }
    guard length > 0 else { throw HakenIPCError.invalidFrame }
    guard length <= HakenIPC.maximumFrameSize else {
      throw HakenIPCError.frameTooLarge(Int(length))
    }
    return try readExactly(Int(length), from: descriptor)
  }

  public static func write(_ data: Data, to descriptor: Int32) throws {
    guard !data.isEmpty else { throw HakenIPCError.invalidFrame }
    guard data.count <= HakenIPC.maximumFrameSize else {
      throw HakenIPCError.frameTooLarge(data.count)
    }
    var length = UInt32(data.count).bigEndian
    try withUnsafeBytes(of: &length) { bytes in
      try writeExactly(bytes, to: descriptor)
    }
    try data.withUnsafeBytes { bytes in
      try writeExactly(bytes, to: descriptor)
    }
  }

  private static func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
    var data = Data(count: count)
    var offset = 0
    try data.withUnsafeMutableBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { throw HakenIPCError.invalidFrame }
      while offset < count {
        let result = Darwin.read(descriptor, baseAddress.advanced(by: offset), count - offset)
        if result == 0 { throw HakenIPCError.endOfStream }
        if result < 0 {
          if errno == EINTR { continue }
          throw HakenIPCError.readFailed(errno)
        }
        offset += result
      }
    }
    return data
  }

  private static func writeExactly(_ bytes: UnsafeRawBufferPointer, to descriptor: Int32) throws {
    guard let baseAddress = bytes.baseAddress else { throw HakenIPCError.invalidFrame }
    var offset = 0
    while offset < bytes.count {
      let result = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
      if result < 0 {
        if errno == EINTR { continue }
        throw HakenIPCError.writeFailed(errno)
      }
      offset += result
    }
  }
}
