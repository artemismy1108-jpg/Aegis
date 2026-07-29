// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "Aegis",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "aegis", targets: ["Aegis"])
    ],
    targets: [
        .executableTarget(name: "Aegis")
    ]
)
