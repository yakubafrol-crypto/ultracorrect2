// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [.library(name: "UCCore", targets: ["UCCore"])]
var targets: [Target] = [.target(name: "UCCore"), .testTarget(name: "UCCoreTests", dependencies: ["UCCore"])]
for name in ["uc-sim", "uc-eval", "uc-resources"] {
    products.append(.executable(name: name, targets: [name]))
    targets.append(.executableTarget(name: name, dependencies: ["UCCore"]))
}
#if os(macOS)
products += [.library(name: "UCPlatform", targets: ["UCPlatform"]), .library(name: "UCNeural", targets: ["UCNeural"])]
targets += [.target(name: "UCPlatform", dependencies: ["UCCore"]), .target(name: "UCNeural", dependencies: ["UCCore"]),
            .testTarget(name: "UCPlatformTests", dependencies: ["UCPlatform"])]
for name in ["uc-bench", "uc-layout-dump"] {
    products.append(.executable(name: name, targets: [name]))
    targets.append(.executableTarget(name: name, dependencies: ["UCCore", "UCPlatform"]))
}
#endif
let package = Package(name: "UltraCorrect2", platforms: [.macOS(.v15)], products: products, targets: targets,
                      swiftLanguageModes: [.v6])
