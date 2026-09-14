// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "VividHomeCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [
    .library(name: "VividHomeCore", targets: ["VividHomeCore"]),
    // Writes a session using only the core, so the pipeline's validator can be
    // pointed at real Swift output. Built by CI, not shipped in the app.
    .executable(name: "vividhome-fixture", targets: ["vividhome-fixture"]),
  ],
  targets: [
    .target(name: "VividHomeCore"),
    .executableTarget(name: "vividhome-fixture", dependencies: ["VividHomeCore"]),
    .testTarget(name: "VividHomeCoreTests", dependencies: ["VividHomeCore"]),
  ]
)
