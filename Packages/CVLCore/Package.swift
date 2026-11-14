// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CVLCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CVLCore", targets: ["CVLCore"]),
    ],
    targets: [
        .target(
            name: "CVLCore",
            // OpenCC 词典和词汇规则，由 scripts/export-shared.mjs 从扩展版导出。
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "CVLCoreTests", dependencies: ["CVLCore"]),
    ]
)
