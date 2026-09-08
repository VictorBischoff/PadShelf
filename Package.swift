// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PadShelf", platforms: [.macOS(.v13)], products: [.executable(name: "PadShelf", targets: ["PadShelf"])], targets: [.executableTarget(name: "PadShelf"), .testTarget(name: "PadShelfTests", dependencies: ["PadShelf"])])
