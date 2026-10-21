// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Slotter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Slotter", targets: ["Slotter"]),
        .executable(name: "slotter-icongen", targets: ["SlotterIconGen"]),
    ],
    targets: [
        .target(name: "SlotterKit"),
        .target(name: "SlotterUI", dependencies: ["SlotterKit"]),
        .executableTarget(name: "Slotter", dependencies: ["SlotterKit", "SlotterUI"]),
        .executableTarget(name: "SlotterIconGen"),
        .testTarget(name: "SlotterKitTests", dependencies: ["SlotterKit", "SlotterUI"]),
    ]
)
