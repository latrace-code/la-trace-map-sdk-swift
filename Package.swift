// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LaTraceMapSDK",
    platforms: [
        .iOS(.v15),
        // macOS is declared so the package compiles on the developer
        // machine (Combine + WKWebView require macOS 10.15+/11+). The
        // public product is still iOS-first.
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "LaTraceMapSDK",
            targets: ["LaTraceMapSDK"]
        )
    ],
    targets: [
        .target(
            name: "LaTraceMapSDK"
        ),
        .testTarget(
            name: "LaTraceMapSDKTests",
            dependencies: ["LaTraceMapSDK"]
        )
    ]
)
