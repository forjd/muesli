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
    targets: [
        .executableTarget(
            name: "Muesli",
            resources: [
                .copy("Resources/parakeet_transcribe.py")
            ]
        )
    ]
)
