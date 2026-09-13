// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TeXium",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TeXiumCore", targets: ["TeXiumCore"]), .executable(name: "TeXium", targets: ["TeXium"])],
    targets: [
        .target(name: "TeXiumCore"),
        .executableTarget(name: "TeXium", dependencies: ["TeXiumCore"], exclude: ["Resources"]),
        .testTarget(name: "TeXiumCoreTests", dependencies: ["TeXiumCore"])
    ]
)
