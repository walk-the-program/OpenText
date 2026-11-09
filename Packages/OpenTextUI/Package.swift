// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenTextUI",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "OpenTextUI", targets: ["OpenTextUI"]),
    ],
    dependencies: [
        .package(path: "../OpenTextDesign"),
    ],
    targets: [
        .target(name: "OpenTextUI", dependencies: [.product(name: "OpenTextDesign", package: "OpenTextDesign")]),
        .testTarget(name: "OpenTextUITests", dependencies: ["OpenTextUI", .product(name: "OpenTextDesign", package: "OpenTextDesign")]),
    ]
)
