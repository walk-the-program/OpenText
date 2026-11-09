// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenTextDesign",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "OpenTextDesign", targets: ["OpenTextDesign"]),
    ],
    targets: [
        .target(name: "OpenTextDesign", resources: [.process("Fonts")]),
        .testTarget(name: "OpenTextDesignTests", dependencies: ["OpenTextDesign"]),
    ]
)
