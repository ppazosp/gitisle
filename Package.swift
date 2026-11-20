// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "GitIsle",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "GitIsle", targets: ["GitIsle"])],
  targets: [
    .target(name: "IslandCore"),
    .executableTarget(
      name: "GitIsle",
      dependencies: ["IslandCore"]),
    .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
  ]
)
