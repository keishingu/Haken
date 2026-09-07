import Foundation

struct CLIInstaller {
  enum InstallError: LocalizedError {
    case bundledToolMissing
    case destinationOccupied

    var errorDescription: String? {
      switch self {
      case .bundledToolMissing: "The bundled haken command could not be found."
      case .destinationOccupied:
        "~/.local/bin/haken already exists and is not a symbolic link. It was not changed."
      }
    }
  }

  private let fileManager = FileManager.default

  var destinationURL: URL {
    fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/haken")
  }

  var bundledToolURL: URL {
    Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/haken")
  }

  var isInstalled: Bool {
    guard
      let destination = try? fileManager.destinationOfSymbolicLink(atPath: destinationURL.path)
    else { return false }
    return URL(fileURLWithPath: destination).standardizedFileURL
      == bundledToolURL.standardizedFileURL
  }

  func install() throws {
    guard fileManager.isExecutableFile(atPath: bundledToolURL.path) else {
      throw InstallError.bundledToolMissing
    }
    try fileManager.createDirectory(
      at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if (try? fileManager.destinationOfSymbolicLink(atPath: destinationURL.path)) != nil {
      try fileManager.removeItem(at: destinationURL)
    } else if fileManager.fileExists(atPath: destinationURL.path) {
      throw InstallError.destinationOccupied
    }
    try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: bundledToolURL)
  }
}
