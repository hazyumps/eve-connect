// swift-tools-version: 6.0
import PackageDescription

// EVECore, EVECLI and the eve-connect CLI are Foundation-only and build on
// Linux as well as macOS. Only the AppKit/SwiftUI application shell in
// Sources/EVEConnect is macOS-specific, so that target is declared here on
// macOS alone. SwiftPM ignores a Sources/ directory that no target claims,
// which is what makes that conditional declaration safe.
var products: [Product] = [
    .executable(name: "eve-connect", targets: ["EVEConnectCLI"])
]

var targets: [Target] = [
    .target(name: "EVECore"),
    .target(name: "EVECLI", dependencies: ["EVECore"]),
    .executableTarget(name: "EVEConnectCLI", dependencies: ["EVECLI"]),
    .testTarget(name: "EVECoreTests", dependencies: ["EVECore"]),
    .testTarget(name: "EVECLITests", dependencies: ["EVECLI"])
]

#if os(macOS)
products.append(.executable(name: "EVEConnect", targets: ["EVEConnect"]))
targets.append(.executableTarget(name: "EVEConnect", dependencies: ["EVECore"]))
#endif

let package = Package(
    name: "EVEConnect",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
