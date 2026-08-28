import XCTest
@testable import NibbleCore

final class GrokCredentialsTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ json: String) throws -> URL {
        let url = dir.appendingPathComponent("auth.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testReadsBearerKey() throws {
        let url = try write(#"""
        {"https://auth.x.ai::abc":{"key":"tok","auth_mode":"oidc"}}
        """#)
        XCTAssertEqual(try GrokCredentials(url: url).readToken(), "tok")
    }

    func testMissingFileIsNotSignedIn() {
        XCTAssertThrowsError(try GrokCredentials(url: dir.appendingPathComponent("nope.json")).readToken()) { err in
            XCTAssertEqual(err as? GrokCredentials.LookupError, .notSignedIn)
        }
    }

    func testEmptyKeyIsNotSignedIn() throws {
        let url = try write(#"{"https://auth.x.ai::abc":{"key":"","auth_mode":"oidc"}}"#)
        XCTAssertThrowsError(try GrokCredentials(url: url).readToken()) { err in
            XCTAssertEqual(err as? GrokCredentials.LookupError, .notSignedIn)
        }
    }

    func testGarbageIsMalformed() throws {
        let url = try write("nope")
        XCTAssertThrowsError(try GrokCredentials(url: url).readToken()) { err in
            XCTAssertEqual(err as? GrokCredentials.LookupError, .malformed)
        }
    }
}
