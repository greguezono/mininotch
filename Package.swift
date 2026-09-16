// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MiniNotch", platforms: [.macOS(.v14)], products: [.executable(name: "MiniNotch", targets: ["MinimalNotch"])], targets: [.executableTarget(name: "MinimalNotch"), .testTarget(name: "MinimalNotchTests", dependencies: ["MinimalNotch"])], swiftLanguageModes: [.v5])
