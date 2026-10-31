// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShinerCoreKit",
    platforms: [.iOS(.v17), .macOS(.v14), .visionOS(.v2)],
    products: [
        .library(name: "ShinerCoreKit", targets: ["ShinerCoreKit"])
    ],
    dependencies: [
        // The firmware's render library; see docs/architecture.md before moving the pin.
        .package(url: "https://github.com/nevyn/shinercore", revision: "26e94ad912050aaaa6b284c698f42037123c1fab"),
    ],
    targets: [
        .target(name: "ShinerCoreKit", dependencies: [
            .product(name: "ShinerRender", package: "shinercore"),
        ]),
        .testTarget(name: "ShinerCoreKitTests", dependencies: ["ShinerCoreKit"]),
    ]
)
