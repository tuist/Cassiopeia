// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Cassiopeia",
    platforms: [.macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Cassiopeia",
            targets: ["Cassiopeia"]),
        .executable(
            name: "cassiopeia",
            targets: ["local-cassiopeia"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/swiftlang/swift-build.git", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Cassiopeia",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SWBUtil", package: "swift-build"),
            ],
            path: "Sources/Cassiopeia"),
        .executableTarget(
            name: "local-cassiopeia",
            dependencies: ["Cassiopeia"],
            path: "Sources/local-cassiopeia"),
        .testTarget(
            name: "CassiopeiaTests",
            dependencies: ["Cassiopeia"]
        ),
    ]
)
