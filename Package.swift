// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacScreenTranslator",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacScreenTranslator", targets: ["MacScreenTranslator"])],
    targets: [
        .executableTarget(name: "MacScreenTranslator", path: "Sources"),
        .testTarget(name: "MacScreenTranslatorTests", dependencies: ["MacScreenTranslator"])
    ]
)
