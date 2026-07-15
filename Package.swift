// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "GifIt",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "GifItCore", targets: ["GifItCore"]),
    .library(name: "GifItMac", targets: ["GifItMac"]),
    .executable(name: "gif-it", targets: ["GifItApp"]),
  ],
  targets: [
    .target(name: "GifItCore"),
    .target(name: "GifItMac", dependencies: ["GifItCore"]),
    .executableTarget(name: "GifItApp", dependencies: ["GifItCore", "GifItMac"]),
    .testTarget(name: "GifItCoreTests", dependencies: ["GifItCore"]),
    .testTarget(name: "GifItMacTests", dependencies: ["GifItCore", "GifItMac"]),
  ]
)
