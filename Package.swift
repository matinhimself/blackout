// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blackout",
    platforms: [.macOS("26.0")],
    products: [.library(name: "BlackoutCore", targets: ["BlackoutCore"])],
    targets: [
        .target(name: "BlackoutCore", path: "Blackout/Core"),
        .testTarget(name: "BlackoutCoreTests", dependencies: ["BlackoutCore"])
    ]
)
