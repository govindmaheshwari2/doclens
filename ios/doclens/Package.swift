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
    dependencies: [],
    targets: [
        .target(
            name: "doclens",
            // ponytail: no FlutterFramework package dep — that path only exists on
            // Flutter 3.44+, and pubspec allows >=3.16.0. Flutter injects the Flutter
            // module either way; the 3.44 build only warns. Add the dep once the
            // pubspec floor moves to 3.44.
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
