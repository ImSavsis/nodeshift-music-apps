// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NSMCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "NSMCore", targets: ["NSMCore"]),
    ],
    targets: [
        .target(name: "NSMCore"),
        .testTarget(name: "NSMCoreTests", dependencies: ["NSMCore"]),
    ]
)
