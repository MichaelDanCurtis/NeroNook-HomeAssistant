// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "NeroNookHomeAssistant", platforms: [.macOS(.v14)], products: [.executable(name: "HomeAssistantPlugin", targets: ["HomePlugin"])], dependencies: [.package(path: "Vendor/NookPluginSDK")], targets: [
    .target(name: "HomeCore", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(name: "HomePlugin", dependencies: ["HomeCore", .product(name: "NookPluginSDK", package: "NookPluginSDK")], swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "HomeCoreTests", dependencies: ["HomeCore"], swiftSettings: [.swiftLanguageMode(.v5)])])
