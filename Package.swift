// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PhoneBox",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic with no system calls: protocol, signatures, access rules, metric maths. Tested.
        .target(name: "PhoneBoxCore"),
        // The menu bar app: everything that talks to macOS.
        .executableTarget(name: "PhoneBox", dependencies: ["PhoneBoxCore"]),
        .testTarget(name: "PhoneBoxCoreTests", dependencies: ["PhoneBoxCore"]),
        .testTarget(name: "PhoneBoxTests", dependencies: ["PhoneBox"]),
    ],
    swiftLanguageModes: [.v5]
)
