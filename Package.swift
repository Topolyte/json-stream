// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JsonStream",
    products: [
        .library(
            name: "JsonStream",
            targets: ["JsonStream"]),
    ],
    targets: [
        .target(
            name: "JsonStream"),
        .testTarget(
            name: "JsonStreamTests",
            dependencies: ["JsonStream"]),
    ]
)
