// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Muesli",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Muesli", targets: ["Muesli"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "Muesli",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            resources: [
                .copy("Resources/parakeet_transcribe.py")
            ]
        )
    ]
)
