// swift-tools-version:5.9
import PackageDescription

// The iOS app itself is compiled on macOS by tools/build-ipa.sh (locally on a
// Mac, or in GitHub Actions). This package exists so the *logic* can be tested
// with `swift test` on any machine with a Swift toolchain.
let package = Package(
    name: "WordCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "WordCore", targets: ["WordCore"])
    ],
    targets: [
        .target(
            name: "WordCore",
            path: "Sources/WordCore"
        ),
        .testTarget(
            name: "WordCoreTests",
            dependencies: ["WordCore"],
            path: "Tests/CoreTests"
        )
    ]
)
