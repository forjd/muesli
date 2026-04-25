// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Muesli",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Muesli", targets: ["Muesli"]),
        .executable(name: "MuesliTests", targets: ["MuesliTests"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "Muesli",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        .executableTarget(
            name: "MuesliTests",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Tests/MuesliTests"
        )
    ]
)
