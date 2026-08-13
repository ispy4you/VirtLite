// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VirtLite",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "VirtLite", targets: ["VirtLite"]),
        .executable(name: "virtlite-boot", targets: ["virtlite-boot"]),
        .library(name: "VirtLiteCore", targets: ["VirtLiteCore"]),
        .library(name: "VirtLiteVZ", targets: ["VirtLiteVZ"]),
    ],
    targets: [
        // Platform-agnostic engine. Must never depend on Virtualization (ARC-01).
        .target(name: "VirtLiteCore"),

        // The Virtualization.framework backend.
        .target(name: "VirtLiteVZ", dependencies: ["VirtLiteCore"]),

        // The application. Built into a signed .app bundle by Scripts/build-app.sh —
        // `swift run` produces an unsigned binary, and an unsigned binary carries no
        // entitlements, so it cannot start a guest.
        .executableTarget(name: "VirtLite", dependencies: ["VirtLiteCore", "VirtLiteVZ"]),

        // Headless proof of concept: boots a guest with no interface, console on the terminal.
        // Kept in the repository because it stays the fastest way to tell a backend problem
        // apart from an interface one.
        .executableTarget(name: "virtlite-boot", dependencies: ["VirtLiteCore", "VirtLiteVZ"]),

        .testTarget(name: "VirtLiteCoreTests", dependencies: ["VirtLiteCore"]),
    ]
)
