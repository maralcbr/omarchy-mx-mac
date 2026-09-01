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
    .library(
      name: "OmarchyInstallerUXCore",
      targets: ["OmarchyInstallerUXCore"]
    ),
    .executable(
      name: "OmarchyAppleInstallerApp",
      targets: ["OmarchyAppleInstallerApp"]
    ),
    .executable(
      name: "OmarchyAppleInstallerHelper",
      targets: ["OmarchyAppleInstallerHelper"]
    ),
    .executable(
      name: "OmarchyCanaryCandidateTool",
      targets: ["OmarchyCanaryCandidateTool"]
    ),
    .executable(
      name: "OmarchyCanaryPhysicalTool",
      targets: ["OmarchyCanaryPhysicalTool"]
    ),
  ],
  targets: [
    .target(
      name: "OmarchyInstallerSystem",
      path: "Sources/OmarchyInstallerSystem",
      publicHeadersPath: "include"
    ),
    .target(
      name: "OmarchyAppleInstallerTrustCore",
      dependencies: ["OmarchyInstallerSystem"],
      path: "Sources/OmarchyAppleInstaller"
    ),
    .target(
      name: "OmarchyInstallerUXCore",
      dependencies: ["OmarchyAppleInstallerTrustCore"],
      path: "Sources/OmarchyInstallerUXCore"
    ),
    .executableTarget(
      name: "OmarchyAppleInstallerApp",
      dependencies: [
        "OmarchyAppleInstallerTrustCore",
        "OmarchyInstallerUXCore",
      ],
      path: "Sources/OmarchyAppleInstallerApp",
      resources: [.copy("Resources/omarchy-icon.png")]
    ),
    .executableTarget(
      name: "OmarchyAppleInstallerHelper",
      dependencies: ["OmarchyAppleInstallerTrustCore"],
      path: "Sources/OmarchyAppleInstallerHelper"
    ),
    .executableTarget(
      name: "OmarchyCanaryCandidateTool",
      dependencies: ["OmarchyAppleInstallerTrustCore"],
      path: "Sources/OmarchyCanaryCandidateTool"
    ),
    .executableTarget(
      name: "OmarchyCanaryPhysicalTool",
      dependencies: ["OmarchyAppleInstallerTrustCore"],
      path: "Sources/OmarchyCanaryPhysicalTool"
    ),
    .testTarget(
      name: "OmarchyAppleInstallerTrustCoreTests",
      dependencies: ["OmarchyAppleInstallerTrustCore"],
      path: "Tests/OmarchyAppleInstallerTrustCoreTests"
    ),
    .testTarget(
      name: "OmarchyInstallerLifecycleTests",
      dependencies: ["OmarchyAppleInstallerTrustCore"],
      path: "Tests/OmarchyInstallerLifecycleTests"
    ),
    .testTarget(
      name: "OmarchyInstallerUXCoreTests",
      dependencies: ["OmarchyInstallerUXCore"],
      path: "Tests/OmarchyInstallerUXCoreTests"
    ),
  ]
)
