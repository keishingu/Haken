// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Haken",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "HakenCore", targets: ["HakenCore"]),
    .executable(name: "Haken", targets: ["HakenApp"]),
    // The internal product name must differ by more than case on the default macOS filesystem.
    .executable(name: "haken-cli", targets: ["HakenCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0")
  ],
  targets: [
    .target(name: "HakenCore"),
    .executableTarget(
      name: "HakenApp",
      dependencies: ["HakenCore"],
      linkerSettings: [.linkedFramework("Carbon")]
    ),
    .executableTarget(
      name: "HakenCLI",
      dependencies: [
        "HakenCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(name: "HakenCoreTests", dependencies: ["HakenCore"]),
  ],
  swiftLanguageModes: [.v5]
)
