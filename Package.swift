// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-continuous-integration",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
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
