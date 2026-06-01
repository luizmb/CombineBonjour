// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "CombineBonjour",
    platforms: [
        .iOS(.v13), .tvOS(.v13), .macOS(.v10_15), .watchOS(.v6)
    ],
    products: [
        .library(name: "CombineBonjour", targets: ["CombineBonjour"]),
        .library(name: "CombineBonjourDynamic", type: .dynamic, targets: ["CombineBonjour"]),
    ],
    dependencies: [
        .package(url: "https://github.com/teufelaudio/NetworkExtensions.git", from: "0.1.9")
    ],
    targets: [
        .target(name: "CombineBonjour", dependencies: ["NetworkExtensions"])
    ]
)
