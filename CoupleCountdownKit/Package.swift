// swift-tools-version:5.10
import PackageDescription

// Platform version is a placeholder — DESIGN.md §4's policy is "latest
// publicly released iOS at build time," so bump this to match whenever
// the project is actually built.
let package = Package(
    name: "CoupleCountdownKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CoupleCountdownKit", targets: ["CoupleCountdownKit"])
    ],
    targets: [
        .target(name: "CoupleCountdownKit"),
        .testTarget(name: "CoupleCountdownKitTests", dependencies: ["CoupleCountdownKit"])
    ]
)
