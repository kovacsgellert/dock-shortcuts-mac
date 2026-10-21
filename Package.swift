// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "dock-utils-mac",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "dock-utils", targets: ["dock-utils"])
  ],
  targets: [
    .executableTarget(
      name: "dock-utils",
      path: "src"
    )
  ]
)
