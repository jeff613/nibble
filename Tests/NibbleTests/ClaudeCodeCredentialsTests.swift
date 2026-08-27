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

    // MARK: Keychain via the security tool

    /// Writes an executable stand-in for /usr/bin/security that logs its
    /// arguments and behaves as scripted.
    func securityStub(_ script: String) throws -> URL {
        let url = dir.appendingPathComponent("security-stub")
        try "#!/bin/sh\necho \"$@\" > \"\(dir.path)/args\"\n\(script)\n"
            .write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testReadsTokenFromKeychainViaSecurityTool() throws {
        let stub = try securityStub(#"echo '{"claudeAiOauth":{"accessToken":"tok-from-keychain"}}'"#)
        let creds = ClaudeCodeCredentials(
            fallbackURL: dir.appendingPathComponent("absent.json"),
            useKeychain: true, securityTool: stub)
        XCTAssertEqual(try creds.readToken(), "tok-from-keychain")

        let args = try String(contentsOf: dir.appendingPathComponent("args"), encoding: .utf8)
        XCTAssertTrue(args.contains("find-generic-password"), "unexpected args: \(args)")
        XCTAssertTrue(args.contains("Claude Code-credentials"), "unexpected args: \(args)")
        XCTAssertTrue(args.contains("-w"), "unexpected args: \(args)")
    }

    func testFallsBackToFileWhenKeychainItemMissing() throws {
        let stub = try securityStub("exit 44")  // errSecItemNotFound
        let url = try credentialsFile(#"{"claudeAiOauth":{"accessToken":"tok-from-file"}}"#)
        let creds = ClaudeCodeCredentials(fallbackURL: url, useKeychain: true, securityTool: stub)
        XCTAssertEqual(try creds.readToken(), "tok-from-file")
    }

    func testLockedKeychainThrowsAccessDeniedWithoutFileFallback() throws {
        let stub = try securityStub("exit 36")  // errSecInteractionNotAllowed
        let url = try credentialsFile(#"{"claudeAiOauth":{"accessToken":"tok-from-file"}}"#)
        let creds = ClaudeCodeCredentials(fallbackURL: url, useKeychain: true, securityTool: stub)
        XCTAssertThrowsError(try creds.readToken()) { error in
            XCTAssertEqual(error as? ClaudeCodeCredentials.LookupError, .accessDenied)
        }
    }

    func testUnexpectedSecurityFailureSurfacesExitCode() throws {
        let stub = try securityStub("exit 3")
        let creds = ClaudeCodeCredentials(
            fallbackURL: dir.appendingPathComponent("absent.json"),
            useKeychain: true, securityTool: stub)
        XCTAssertThrowsError(try creds.readToken()) { error in
            XCTAssertEqual(error as? ClaudeCodeCredentials.LookupError, .keychain(3))
        }
    }

    // MARK: Caching

    func testTokenIsReadOnceAndThenCached() throws {
        let url = try credentialsFile(#"{"claudeAiOauth":{"accessToken":"first"}}"#)
        let creds = ClaudeCodeCredentials(fallbackURL: url, useKeychain: false)
        XCTAssertEqual(try creds.readToken(), "first")

        // Removing the source proves the second read never went back to it.
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(try creds.readToken(), "first")
    }

    func testReloadBypassesTheCache() throws {
        let url = try credentialsFile(#"{"claudeAiOauth":{"accessToken":"first"}}"#)
        let creds = ClaudeCodeCredentials(fallbackURL: url, useKeychain: false)
        XCTAssertEqual(try creds.readToken(), "first")

        _ = try credentialsFile(#"{"claudeAiOauth":{"accessToken":"rotated"}}"#)
        XCTAssertEqual(try creds.readToken(), "first", "cached until asked to reload")
        XCTAssertEqual(try creds.readToken(reload: true), "rotated")
        XCTAssertEqual(try creds.readToken(), "rotated", "reload refreshes the cache")
    }

    func testFailedReadIsNotCached() throws {
        let url = dir.appendingPathComponent(".credentials.json")
        let creds = ClaudeCodeCredentials(fallbackURL: url, useKeychain: false)
        XCTAssertThrowsError(try creds.readToken())

        _ = try credentialsFile(#"{"claudeAiOauth":{"accessToken":"arrived-late"}}"#)
        XCTAssertEqual(try creds.readToken(), "arrived-late")
    }

    func testErrorMessagesAreActionable() {
        XCTAssertTrue(ClaudeCodeCredentials.LookupError.notSignedIn
            .errorDescription!.contains("claude"))
        XCTAssertTrue(ClaudeCodeCredentials.LookupError.accessDenied
            .errorDescription!.contains("Keychain Access"))
    }
}
