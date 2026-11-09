// swift-tools-version: 6.0
import PackageDescription

// App-side pure logic (no UI, no engine): hotkey parsing, opentext:// routing,
// file-type routing, password rules, text coding, safe saves. Shared by the app and the Finder extension.
let package = Package(
    name: "OpenTextAppLogic",
    platforms: [.macOS("26.0")],
    products: [.library(name: "OpenTextAppLogic", targets: ["OpenTextAppLogic"])],
    dependencies: [.package(path: "../../Packages/OpenTextKit")],
    targets: [
        .target(name: "OpenTextAppLogic", dependencies: [.product(name: "OpenTextKit", package: "OpenTextKit")]),
        .testTarget(name: "OpenTextAppLogicTests", dependencies: ["OpenTextAppLogic"]),
    ]
)
