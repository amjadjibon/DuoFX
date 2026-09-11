// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DuoFX",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DuoFX", targets: ["DuoFX"])],
    targets: [
        .target(name: "DuoFXCore", path: "DuoFX/Models"),
        .executableTarget(
            name: "DuoFX", dependencies: ["DuoFXCore"], path: "DuoFX",
            exclude: ["Models", "Info.plist"],
            resources: [.copy("Rendering/Shaders.metal"), .copy("Resources/Preview.png")],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"), .linkedFramework("MetalKit"),
                .linkedFramework("MetalPerformanceShaders"), .linkedFramework("IOKit")
            ]
        ),
        .testTarget(name: "DuoFXTests", dependencies: ["DuoFXCore", "DuoFX"], path: "Tests")
    ]
)
