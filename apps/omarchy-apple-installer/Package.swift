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
    ),
    .executable(
      name: "OmarchyAppleInstallerApp",
      targets: ["OmarchyAppleInstallerApp"]
    ),
  ],
  targets: [
    .target(
      name: "OmarchyAppleInstallerTrustCore",
      path: "Sources/OmarchyAppleInstaller"
    ),
    .executableTarget(
      name: "OmarchyAppleInstallerApp",
      dependencies: ["OmarchyAppleInstallerTrustCore"],
      path: "Sources/OmarchyAppleInstallerApp"
    ),
    .testTarget(
      name: "OmarchyAppleInstallerTrustCoreTests",
      dependencies: ["OmarchyAppleInstallerTrustCore"],
      path: "Tests/OmarchyAppleInstallerTrustCoreTests"
    ),
  ]
)
