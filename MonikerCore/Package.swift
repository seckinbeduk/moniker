// swift-tools-version: 6.2
import PackageDescription

// Everything Moniker decides without the model: which files to touch, how to name them,
// how to undo. Tested on its own with `swift test`.
let package = Package(
    name: "MonikerCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MonikerCore", targets: ["MonikerCore"]),
    ],
    targets: [
        .target(name: "MonikerCore"),
        .testTarget(name: "MonikerCoreTests", dependencies: ["MonikerCore"]),
    ]
)
