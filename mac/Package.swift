// swift-tools-version: 6.0
import PackageDescription

// ykit/swift is a sibling checkout (hub\Y-Family\ykit next to hub\Y-Family\snappy), consumed as a
// local SwiftPM package rather than copied source — the Swift equivalent of how ykit/wpf is
// linked into the WPF apps' .csproj files. See ykit/docs/desk-design-system.md section 5.
let package = Package(
    name: "Snappy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Snappy", targets: ["Snappy"]),
        .executable(name: "snappy-icongen", targets: ["SnappyIconGen"]),
    ],
    dependencies: [
        .package(path: "../../ykit/swift"),
    ],
    targets: [
        .target(name: "SnappyKit"),
        .target(name: "SnappyUI", dependencies: ["SnappyKit", .product(name: "DeskTheme", package: "swift")]),
        .executableTarget(name: "Snappy", dependencies: ["SnappyKit", "SnappyUI"]),
        .executableTarget(name: "SnappyIconGen"),
        .testTarget(name: "SnappyKitTests", dependencies: ["SnappyKit"]),
    ]
)
