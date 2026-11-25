// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PhoneBox",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic with no system calls: protocol, signatures, access rules, metric maths. Tested.
        .target(name: "PhoneBoxCore"),
        .testTarget(name: "PhoneBoxCoreTests", dependencies: ["PhoneBoxCore"]),
    ],
    swiftLanguageModes: [.v5]
)
