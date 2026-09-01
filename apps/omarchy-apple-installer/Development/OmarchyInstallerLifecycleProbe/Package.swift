// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "OmarchyInstallerLifecycleProbe",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "OmarchyInstallerLifecycleProbe",
      dependencies: [
        .product(
          name: "OmarchyAppleInstallerTrustCore",
          package: "omarchy-apple-installer"
        )
      ]
    )
  ]
)
