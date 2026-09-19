// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacToys",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacToys", targets: ["MacToys"])],
    targets: [
        .target(name: "MacToysCore"),
        .executableTarget(name: "MacToys", dependencies: ["MacToysCore"]),
        .testTarget(name: "MacToysCoreTests", dependencies: ["MacToysCore"])
    ]
)
