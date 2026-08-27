// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "OmarchyAppleInstallerTrustCore",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(
      name: "OmarchyAppleInstallerTrustCore",
      targets: ["OmarchyAppleInstallerTrustCore"]
    )
  ],
  targets: [
    .target(
      name: "OmarchyAppleInstallerTrustCore",
      path: "Sources/OmarchyAppleInstaller"
    ),
    .testTarget(
      name: "OmarchyAppleInstallerTrustCoreTests",
      dependencies: ["OmarchyAppleInstallerTrustCore"],
      path: "Tests/OmarchyAppleInstallerTrustCoreTests"
    ),
  ]
)
