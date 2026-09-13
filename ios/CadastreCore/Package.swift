// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CadastreCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [.library(name: "CadastreCore", targets: ["CadastreCore"])],
  targets: [
    .target(name: "CadastreCore"),
    .testTarget(name: "CadastreCoreTests", dependencies: ["CadastreCore"]),
  ]
)
