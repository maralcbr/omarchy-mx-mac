#if os(macOS)
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  @testable import OmarchyInstallerUXCore

  final class ReleaseChannelPreferenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
      suiteName = "omarchy-channel-\(UUID().uuidString)"
      defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
      defaults.removePersistentDomain(forName: suiteName)
      super.tearDown()
    }

    func testAnUnsetPreferenceUsesTheDescriptorDefault() {
      let preference = ReleaseChannelPreference(defaults: defaults)

      XCTAssertNil(preference.stored)
      XCTAssertEqual(preference.resolve(descriptorDefault: .stable), .stable)
      XCTAssertEqual(preference.resolve(descriptorDefault: .rc), .rc)
    }

    func testSelectingBetaIsRemembered() {
      let preference = ReleaseChannelPreference(defaults: defaults)

      preference.select(.rc)

      XCTAssertEqual(preference.stored, .rc)
      XCTAssertEqual(preference.resolve(descriptorDefault: .stable), .rc)
    }

    func testClearingThePreferenceReturnsToTheDefault() {
      let preference = ReleaseChannelPreference(defaults: defaults)
      preference.select(.rc)

      preference.select(nil)

      XCTAssertNil(preference.stored)
      XCTAssertEqual(preference.resolve(descriptorDefault: .stable), .stable)
    }

    func testAnUnknownStoredValueFallsBackToTheDefault() {
      // A hand-edited or stale preference must never leave the app reading a
      // channel this build does not know.
      defaults.set("nightly", forKey: ReleaseChannelPreference.defaultsKey)
      let preference = ReleaseChannelPreference(defaults: defaults)

      XCTAssertNil(preference.stored)
      XCTAssertEqual(preference.resolve(descriptorDefault: .stable), .stable)
    }

    func testAFreshLaunchShowsAndFetchesTheBundledDefault() throws {
      let configuration = try InstallerReleaseConfigurationLocator().load(
        from: Self.packageRoot.appendingPathComponent("Release", isDirectory: true))
      let preference = ReleaseChannelPreference(defaults: defaults)

      XCTAssertNil(preference.stored)
      XCTAssertEqual(preference.resolve(configuration: configuration), configuration.defaultChannel)
    }

    func testASavedChoiceWinsOverTheBundledDefault() throws {
      let configuration = try InstallerReleaseConfigurationLocator().load(
        from: Self.packageRoot.appendingPathComponent("Release", isDirectory: true))
      let other = try XCTUnwrap(
        ReleaseChannel.allCases.first { $0 != configuration.defaultChannel })
      let preference = ReleaseChannelPreference(defaults: defaults)

      preference.select(other)

      XCTAssertEqual(preference.resolve(configuration: configuration), other)
    }

    func testTheWindowAndTheDownloadResolveTheChannelTheSameWay() throws {
      // A window-side fallback of its own once showed Stable while the
      // download fetched the bundled rc default.
      let app = Self.packageRoot.appendingPathComponent("Sources/OmarchyAppleInstallerApp")
      var offenders = [String]()
      let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)
      while let file = files?.nextObject() as? URL {
        guard file.pathExtension == "swift" else { continue }
        let text = try String(contentsOf: file, encoding: .utf8)
        if text.contains("descriptorDefault") { offenders.append(file.lastPathComponent) }
      }
      XCTAssertEqual(offenders, [])

      let scene = try String(
        contentsOf: app.appendingPathComponent("OmarchyAppleInstallerApp.swift"), encoding: .utf8)
      let download = try String(
        contentsOf: app.appendingPathComponent("LiveInstallerEnvironment.swift"), encoding: .utf8)
      // Wiring guard only; the resolver's behaviour is tested above.
      XCTAssertTrue(
        scene.contains(
          "@State private var channel = ReleaseChannelPreference().resolveFromMainBundle()\n"))
      XCTAssertTrue(
        scene.contains("environment: InstallerEnvironmentFactory.make(), channel: channel,"))
      XCTAssertFalse(scene.contains("channel = ."))
      XCTAssertTrue(download.contains("ReleaseChannelPreference().resolve(configuration: configuration)"))
    }

    private static var packageRoot: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    }
  }
#endif
