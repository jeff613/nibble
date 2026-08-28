import XCTest
@testable import NibbleCore

final class CodexCredentialsTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ json: String, name: String = "auth.json") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testReadsAccessTokenAndAccountID() throws {
        let url = try write(#"{"tokens":{"access_token":"tok","account_id":"acct"}}"#)
        let tok = try CodexCredentials(url: url).readToken()
        XCTAssertEqual(tok.accessToken, "tok")
        XCTAssertEqual(tok.accountID, "acct")
    }

    func testAccountIDIsOptional() throws {
        let url = try write(#"{"tokens":{"access_token":"tok"}}"#)
        let tok = try CodexCredentials(url: url).readToken()
        XCTAssertEqual(tok.accessToken, "tok")
        XCTAssertNil(tok.accountID)
    }

    func testMissingFileIsNotSignedIn() {
        let url = dir.appendingPathComponent("absent.json")
        XCTAssertThrowsError(try CodexCredentials(url: url).readToken()) { err in
            XCTAssertEqual(err as? CodexCredentials.LookupError, .notSignedIn)
        }
    }

    func testEmptyAccessTokenIsNotSignedIn() throws {
        let url = try write(#"{"tokens":{"access_token":"","account_id":"acct"}}"#)
        XCTAssertThrowsError(try CodexCredentials(url: url).readToken()) { err in
            XCTAssertEqual(err as? CodexCredentials.LookupError, .notSignedIn)
        }
    }

    func testGarbageIsMalformed() throws {
        let url = try write("nope")
        XCTAssertThrowsError(try CodexCredentials(url: url).readToken()) { err in
            XCTAssertEqual(err as? CodexCredentials.LookupError, .malformed)
        }
    }
}
