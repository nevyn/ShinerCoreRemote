// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShinerCoreKit",
    platforms: [.iOS(.v17), .macOS(.v14), .visionOS(.v2)],
    products: [
        .library(name: "ShinerCoreKit", targets: ["ShinerCoreKit"])
    ],
    targets: [
        .target(name: "ShinerCoreKit"),
        .testTarget(name: "ShinerCoreKitTests", dependencies: ["ShinerCoreKit"]),
    ]
)
