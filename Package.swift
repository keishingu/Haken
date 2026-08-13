// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Haken",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "HakenCore", targets: ["HakenCore"]),
    .executable(name: "Haken", targets: ["HakenApp"]),
  ],
  targets: [
    .target(name: "HakenCore"),
    .executableTarget(
      name: "HakenApp",
      dependencies: ["HakenCore"],
      linkerSettings: [.linkedFramework("Carbon")]
    ),
    .testTarget(name: "HakenCoreTests", dependencies: ["HakenCore"]),
  ],
  swiftLanguageModes: [.v5]
)
