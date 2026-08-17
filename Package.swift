// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-continuous-integration",
    platforms: [
        .macOS("27"),
        .iOS("27"),
        .tvOS("27"),
        .watchOS("27"),
        .visionOS("27"),
    ],
    products: [
        .library(
            name: "Continuous Integration",
            targets: ["ContinuousIntegration"]
        ),
    ],
    targets: [
        // The vendor-neutral continuous-integration domain: plans,
        // requirements, verdicts and execution semantics. Sole generic-CI
        // owner (amendment 4 clause 1); nothing GitHub-specific or
        // Institute-specific belongs here — the GitHub↔CI relation and
        // Institute policy live with their own owners.
        .target(
            name: "ContinuousIntegration"
        ),
        .testTarget(
            name: "ContinuousIntegration Tests",
            dependencies: ["ContinuousIntegration"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
