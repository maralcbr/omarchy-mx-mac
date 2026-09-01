#if os(macOS)
  import Foundation
  import OmarchyAppleInstallerTrustCore
  import XCTest

  @testable import OmarchyInstallerUXCore

  final class CredentialInputTests: XCTestCase {
    /// The sheet's enabled state must agree with the real authorization
    /// initializer for every case, or the button would lie.
    func testValidityMatchesMachineOwnerAuthorization() {
      let usernames = [
        "", "owner", "own.er", "own_er", "own-er", "Owner1",
        "owner name", "owner!", "øwner",
        String(repeating: "a", count: 255),
        String(repeating: "a", count: 256),
      ]
      let passwords = [
        "", "p", "pass word",
        String(repeating: "p", count: 1_024),
        String(repeating: "p", count: 1_025),
        "line\nbreak", "carriage\rreturn", "nul\u{0}byte",
      ]

      for username in usernames {
        for password in passwords {
          let input = CredentialInput(username: username, password: password)
          let expected =
            (try? MachineOwnerAuthorization(
              username: username,
              password: Data(password.utf8)
            )) != nil
          XCTAssertEqual(
            input.isValid,
            expected,
            "mismatch for username \(username.count) chars, password \(password.count) chars"
          )
        }
      }
    }

    func testReasonsExplainOnlyRealRejections() {
      XCTAssertNil(CredentialInput(username: "", password: "").usernameReason)
      XCTAssertNil(CredentialInput(username: "owner", password: "").usernameReason)
      XCTAssertNotNil(
        CredentialInput(username: "owner name", password: "").usernameReason
      )
      XCTAssertNotNil(
        CredentialInput(
          username: String(repeating: "a", count: 256),
          password: ""
        ).usernameReason
      )

      XCTAssertNil(CredentialInput(username: "owner", password: "").passwordReason)
      XCTAssertNil(
        CredentialInput(username: "owner", password: "good").passwordReason
      )
      XCTAssertNotNil(
        CredentialInput(username: "owner", password: "bad\nvalue").passwordReason
      )
      XCTAssertNotNil(
        CredentialInput(
          username: "owner",
          password: String(repeating: "p", count: 1_025)
        ).passwordReason
      )
    }

    func testClearPasswordKeepsTheUserName() {
      var input = CredentialInput(username: "owner", password: "secret")

      input.clearPassword()

      XCTAssertEqual(input.username, "owner")
      XCTAssertTrue(input.password.isEmpty)
      XCTAssertFalse(input.isValid)
    }

    func testValidatedProducesTheRealAuthorization() throws {
      let input = CredentialInput(username: "owner", password: "secret")

      let authorization = try XCTUnwrap(input.validated())

      XCTAssertEqual(authorization.username, "owner")
    }
  }
#endif
