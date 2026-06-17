// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ZoomCaptionTranslator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ZoomCaptionCore",
            targets: ["ZoomCaptionCore"]
        ),
        .executable(
            name: "zoom-caption-translator",
            targets: ["ZoomCaptionTranslator"]
        )
    ],
    targets: [
        .target(name: "ZoomCaptionCore"),
        .executableTarget(
            name: "ZoomCaptionTranslator",
            dependencies: ["ZoomCaptionCore"]
        ),
        .testTarget(
            name: "ZoomCaptionCoreTests",
            dependencies: ["ZoomCaptionCore"]
        )
    ]
)
