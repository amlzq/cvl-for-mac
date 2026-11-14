// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CVLCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CVLCore", targets: ["CVLCore"]),
    ],
    targets: [
        .target(name: "CVLCore"),
        .testTarget(name: "CVLCoreTests", dependencies: ["CVLCore"]),
    ]
)
