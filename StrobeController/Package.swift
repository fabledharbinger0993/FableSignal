// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StrobeController",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "StrobeController", targets: ["StrobeController"]),
    ],
    targets: [
        .target(name: "StrobeController"),
        .testTarget(
            name: "StrobeControllerTests",
            dependencies: ["StrobeController"]
        ),
    ]
)
