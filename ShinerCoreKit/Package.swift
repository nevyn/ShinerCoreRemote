// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShinerCoreKit",
    platforms: [.iOS(.v17), .macOS(.v14), .visionOS(.v2)],
    products: [
        .library(name: "ShinerCoreKit", targets: ["ShinerCoreKit"])
    ],
    dependencies: [
        // The firmware's render library; becomes a URL + revision pin once the firmware PR merges.
        .package(path: "../../../../../shinercore/.claude/worktrees/strip-preview"),
    ],
    targets: [
        .target(name: "ShinerCoreKit", dependencies: [
            .product(name: "ShinerRender", package: "strip-preview"),
        ]),
        .testTarget(name: "ShinerCoreKitTests", dependencies: ["ShinerCoreKit"]),
    ]
)
