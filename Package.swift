// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MinimalNotch", platforms: [.macOS(.v14)], products: [.executable(name: "MinimalNotch", targets: ["MinimalNotch"])], targets: [.executableTarget(name: "MinimalNotch"), .testTarget(name: "MinimalNotchTests", dependencies: ["MinimalNotch"])], swiftLanguageModes: [.v5])
