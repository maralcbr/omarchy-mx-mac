#if os(macOS)
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class MachineOwnerAuthorizationTests: XCTestCase {
    func testValidLocalAccountAndPasswordAreAccepted() throws {
      XCTAssertNoThrow(
        try MachineOwnerAuthorization(
          username: "mina",
          password: Data("owner-password".utf8)
        )
      )
    }

    func testShellMetacharactersAreRejectedFromUsername() {
      XCTAssertThrowsError(
        try MachineOwnerAuthorization(
          username: "mina;env",
          password: Data("owner-password".utf8)
        )
      ) {
        XCTAssertEqual(
          $0 as? MachineOwnerAuthorizationError,
          .invalidUsername
        )
      }
    }

    func testLineBreaksAreRejectedFromPassword() {
      XCTAssertThrowsError(
        try MachineOwnerAuthorization(
          username: "mina",
          password: Data("owner\npassword".utf8)
        )
      ) {
        XCTAssertEqual(
          $0 as? MachineOwnerAuthorizationError,
          .invalidPassword
        )
      }
    }

    func testOversizedPasswordIsRejected() {
      XCTAssertThrowsError(
        try MachineOwnerAuthorization(
          username: "mina",
          password: Data(repeating: 97, count: 1_025)
        )
      ) {
        XCTAssertEqual(
          $0 as? MachineOwnerAuthorizationError,
          .invalidPassword
        )
      }
    }

    func testNonUTF8PasswordIsRejected() {
      XCTAssertThrowsError(
        try MachineOwnerAuthorization(
          username: "mina",
          password: Data([0xff])
        )
      ) {
        XCTAssertEqual(
          $0 as? MachineOwnerAuthorizationError,
          .invalidPassword
        )
      }
    }
  }
#endif
