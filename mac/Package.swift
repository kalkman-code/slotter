// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Slotter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Slotter", targets: ["Slotter"]),
        .executable(name: "slotter-icongen", targets: ["SlotterIconGen"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "SlotterKit"),
        .target(name: "SlotterUI", dependencies: ["SlotterKit", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "Slotter", dependencies: ["SlotterKit", "SlotterUI"]),
        .executableTarget(name: "SlotterIconGen"),
        .testTarget(name: "SlotterKitTests", dependencies: ["SlotterKit", "SlotterUI"]),
    ]
)
