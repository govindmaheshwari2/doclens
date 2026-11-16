// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "doclens",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "doclens", targets: ["doclens"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "doclens",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
