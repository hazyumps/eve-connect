// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EVEConnect",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EVEConnect", targets: ["EVEConnect"])],
    targets: [
        .target(name: "EVECore"),
        .executableTarget(name: "EVEConnect", dependencies: ["EVECore"]),
        .testTarget(name: "EVECoreTests", dependencies: ["EVECore"])
    ]
)
