// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SessionKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "SessionKit", targets: ["SessionKit"]),
    ],
    targets: [
        .target(name: "SessionKit"),
        .testTarget(
            name: "SessionKitTests",
            dependencies: ["SessionKit"]
        ),
    ]
)
