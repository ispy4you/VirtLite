// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VirtLite",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VirtLiteCore", targets: ["VirtLiteCore"]),
        .library(name: "VirtLiteVZ", targets: ["VirtLiteVZ"]),
    ],
    targets: [
        // Platform-agnostic engine. Must never depend on Virtualization (ARC-01).
        .target(name: "VirtLiteCore"),

        // The Virtualization.framework backend.
        .target(name: "VirtLiteVZ", dependencies: ["VirtLiteCore"]),

        .testTarget(name: "VirtLiteCoreTests", dependencies: ["VirtLiteCore"]),
    ]
)
