// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CadastreCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [
    .library(name: "CadastreCore", targets: ["CadastreCore"]),
    // Writes a session using only the core, so the pipeline's validator can be
    // pointed at real Swift output. Built by CI, not shipped in the app.
    .executable(name: "cadastre-fixture", targets: ["cadastre-fixture"]),
  ],
  targets: [
    .target(name: "CadastreCore"),
    .executableTarget(name: "cadastre-fixture", dependencies: ["CadastreCore"]),
    .testTarget(name: "CadastreCoreTests", dependencies: ["CadastreCore"]),
  ]
)
