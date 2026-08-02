import XCTest
@testable import UsageBarCore

final class CredentialTests: XCTestCase {
    func testExtractsAccessToken() {
        let json = Data(#"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"x"}}"#.utf8)
        XCTAssertEqual(CredentialParser.accessToken(fromJSON: json), "sk-ant-oat01-abc")
    }

    func testReturnsNilForGarbage() {
        XCTAssertNil(CredentialParser.accessToken(fromJSON: Data("nope".utf8)))
        XCTAssertNil(CredentialParser.accessToken(fromJSON: Data("{}".utf8)))
    }
}
