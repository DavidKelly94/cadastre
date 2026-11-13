// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "VividHomeCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [
    .library(name: "VividHomeCore", targets: ["VividHomeCore"]),
    // Lifts a drawing's text, fills and lines out of a PDF (ADR-0032). The one
    // target that needs Apple's frameworks: its sources compile to nothing on
    // Linux, and its tests run on the macOS runner.
    .library(name: "VividHomePDF", targets: ["VividHomePDF"]),
    // Writes a session using only the core, so the pipeline's validator can be
    // pointed at real Swift output. Built by CI, not shipped in the app.
    .executable(name: "vividhome-fixture", targets: ["vividhome-fixture"]),
  ],
  targets: [
    .target(name: "VividHomeCore"),
    .target(name: "VividHomePDF", dependencies: ["VividHomeCore"]),
    .executableTarget(name: "vividhome-fixture", dependencies: ["VividHomeCore"]),
    .testTarget(name: "VividHomeCoreTests", dependencies: ["VividHomeCore"]),
    .testTarget(
      name: "VividHomePDFTests", dependencies: ["VividHomePDF"],
      exclude: ["make_house_sheet.py"], resources: [.copy("Fixtures")]),
  ]
)
