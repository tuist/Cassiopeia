// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Cassiopeia",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "Cassiopeia",
            type: .dynamic,
            targets: ["Cassiopeia"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/swiftlang/swift-build.git", branch: "main"),
    ],
    targets: [
        // The core CAS implementation library with C bridge
        .target(
            name: "Cassiopeia",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SWBUtil", package: "swift-build"),
            ],
            cSettings: [
                .headerSearchPath("include")
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-actor-data-race-checks"])
            ]),
        .testTarget(
            name: "CassiopeiaTests",
            dependencies: ["Cassiopeia"]
        ),
    ]
)
