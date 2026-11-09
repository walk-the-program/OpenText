// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenTextKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OpenTextKit", targets: ["OpenTextKit"]),
        .executable(name: "opentext", targets: ["opentext"]),
        .executable(name: "opentext-mcp", targets: ["opentext-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    ],
    targets: [
        .target(name: "OpenTextKit", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .executableTarget(name: "opentext", dependencies: [
            "OpenTextKit", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "opentext-mcp", dependencies: [
            "OpenTextKit", .product(name: "MCP", package: "swift-sdk")]),
        .testTarget(name: "OpenTextKitTests", dependencies: ["OpenTextKit"]),
    ],
    swiftLanguageModes: [.v6]
)
