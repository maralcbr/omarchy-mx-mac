#if os(macOS)
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class InstallConfTests: XCTestCase {
    func testSerializesFormatEncryptAndLane() throws {
      let conf = try InstallConf(encrypt: true, lane: "rc")
      XCTAssertEqual(conf.serialized, "format=1\nencrypt=1\nlane=rc\n")
      XCTAssertEqual(try InstallConf.parse(conf.serialized), conf)
      XCTAssertEqual(try InstallConf.parse(conf.serializedData), conf)
    }

    func testSerializesOptOutAndEveryAppChannel() throws {
      for lane in ["stable", "rc", "rc-aurora"] {
        let conf = try InstallConf(encrypt: false, lane: lane)
        XCTAssertEqual(conf.serialized, "format=1\nencrypt=0\nlane=\(lane)\n")
        XCTAssertEqual(try InstallConf.parse(conf.serialized).lane, lane)
        XCTAssertFalse(try InstallConf.parse(conf.serialized).encrypt)
      }
    }

    func testRejectsUnknownLanesAndMalformedDocuments() {
      XCTAssertThrowsError(try InstallConf(encrypt: true, lane: "edge")) {
        XCTAssertEqual($0 as? InstallConfError, .invalidLane)
      }
      XCTAssertThrowsError(try InstallConf.parse("format=1\nencrypt=1\n")) {
        XCTAssertEqual($0 as? InstallConfError, .invalidDocument)
      }
      XCTAssertThrowsError(try InstallConf.parse("format=2\nencrypt=1\nlane=rc\n")) {
        XCTAssertEqual($0 as? InstallConfError, .invalidDocument)
      }
      XCTAssertThrowsError(try InstallConf.parse("format=1\nencrypt=yes\nlane=rc\n")) {
        XCTAssertEqual($0 as? InstallConfError, .invalidDocument)
      }
    }
  }
#endif
