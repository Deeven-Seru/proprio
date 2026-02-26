// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Proprio-iOS",
    platforms: [
        .iOS(.v17) // Require iOS 17 for latest AR/Vision features
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "ProprioApp",
            targets: ["ProprioApp"]),
        .library(
            name: "ProprioCore",
            targets: ["ProprioCore"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "ProprioApp",
            dependencies: ["ProprioCore"],
            path: "Sources/ProprioApp"), // Explicit path if needed
        .target(
            name: "ProprioCore",
            dependencies: [],
            path: "Sources/ProprioCore"),
        .testTarget(
            name: "ProprioCoreTests",
            dependencies: ["ProprioCore"]),
    ]
)
