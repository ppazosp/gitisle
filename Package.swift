// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "GitIsle",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "GitIsle", targets: ["GitIsle"])],
  dependencies: [
    .package(
      url: "https://github.com/steipete/CodexBar.git",
      revision: "79831b47517f3e3e340886be63157f582ab13d41")
  ],
  targets: [
    .target(name: "IslandCore"),
    .executableTarget(
      name: "GitIsle",
      dependencies: [
        "IslandCore",
        .product(name: "CodexBarCore", package: "CodexBar"),
      ]),
    .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
  ]
)
