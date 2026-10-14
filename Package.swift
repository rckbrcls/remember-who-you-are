// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RememberWhoYouAre",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2"),
    ],
    targets: [
        .target(name: "RWYACore", path: "Sources/RWYACore"),
        .executableTarget(name: "RememberWhoYouAre", dependencies: ["RWYACore", .product(name: "Sparkle", package: "Sparkle")], path: "Sources/RememberWhoYouAre"),
        .testTarget(name: "RWYACoreTests", dependencies: ["RWYACore"], path: "Tests/RWYACoreTests"),
    ]
)
