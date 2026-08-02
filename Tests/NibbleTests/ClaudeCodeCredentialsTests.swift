import XCTest
@testable import NibbleCore

final class ClaudeCodeCredentialsTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func credentialsFile(_ contents: String) throws -> URL {
        let url = dir.appendingPathComponent(".credentials.json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: JSON extraction

    func testExtractsAccessToken() {
        let json = Data(#"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"x"}}"#.utf8)
        XCTAssertEqual(ClaudeCodeCredentials.accessToken(fromJSON: json), "sk-ant-oat01-abc")
    }

    func testReturnsNilForGarbageOrMissingFields() {
        XCTAssertNil(ClaudeCodeCredentials.accessToken(fromJSON: Data("nope".utf8)))
        XCTAssertNil(ClaudeCodeCredentials.accessToken(fromJSON: Data("{}".utf8)))
        XCTAssertNil(ClaudeCodeCredentials.accessToken(fromJSON: Data(#"{"claudeAiOauth":{}}"#.utf8)))
        XCTAssertNil(ClaudeCodeCredentials.accessToken(fromJSON: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)))
    }

    // MARK: File fallback

    func testReadsTokenFromFallbackFile() throws {
        let url = try credentialsFile(#"{"claudeAiOauth":{"accessToken":"tok-from-file"}}"#)
        let creds = ClaudeCodeCredentials(fallbackURL: url, useKeychain: false)
        XCTAssertEqual(try creds.readToken(), "tok-from-file")
    }

    func testThrowsNotSignedInWhenFileMissing() {
        let creds = ClaudeCodeCredentials(
            fallbackURL: dir.appendingPathComponent("absent.json"), useKeychain: false)
        XCTAssertThrowsError(try creds.readToken()) { error in
            XCTAssertEqual(error as? ClaudeCodeCredentials.LookupError, .notSignedIn)
        }
    }

    func testThrowsNotSignedInWhenFileMalformed() throws {
        let url = try credentialsFile("{ not json")
        let creds = ClaudeCodeCredentials(fallbackURL: url, useKeychain: false)
        XCTAssertThrowsError(try creds.readToken()) { error in
            XCTAssertEqual(error as? ClaudeCodeCredentials.LookupError, .notSignedIn)
        }
    }

    func testErrorMessagesAreActionable() {
        XCTAssertTrue(ClaudeCodeCredentials.LookupError.notSignedIn
            .errorDescription!.contains("claude"))
        XCTAssertTrue(ClaudeCodeCredentials.LookupError.accessDenied
            .errorDescription!.contains("Keychain Access"))
    }
}
