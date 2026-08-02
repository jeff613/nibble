import XCTest
@testable import UsageBarCore

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [(Int, Data)] = []
    nonisolated(unsafe) static var seenAuthHeaders: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seenAuthHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        let (status, body) = Self.responses.isEmpty ? (500, Data()) : Self.responses.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class UsageClientTests: XCTestCase {
    func makeClient(token: String?) -> ClaudeUsageClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return ClaudeUsageClient(session: URLSession(configuration: config)) { token }
    }

    override func setUp() {
        StubProtocol.responses = []
        StubProtocol.seenAuthHeaders = []
    }

    func testFetchParsesWindowsAndSendsBearerToken() async throws {
        StubProtocol.responses = [(200, UsageDecodingTests.fixture)]
        let windows = try await makeClient(token: "tok1").fetchUsage()
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(StubProtocol.seenAuthHeaders, ["Bearer tok1"])
    }

    func testThrowsNotConfiguredWithoutToken() async {
        do {
            _ = try await makeClient(token: nil).fetchUsage()
            XCTFail("should throw")
        } catch UsageClientError.notConfigured {
            XCTAssertTrue(StubProtocol.seenAuthHeaders.isEmpty, "must not hit the network")
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testThrowsUnauthorizedOn401() async {
        StubProtocol.responses = [(401, Data())]
        do {
            _ = try await makeClient(token: "expired").fetchUsage()
            XCTFail("should throw")
        } catch UsageClientError.unauthorized {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testThrowsBadStatusOnServerError() async {
        StubProtocol.responses = [(503, Data())]
        do {
            _ = try await makeClient(token: "tok").fetchUsage()
            XCTFail("should throw")
        } catch UsageClientError.badStatus(let code) {
            XCTAssertEqual(code, 503)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testValidateUsesSuppliedTokenNotStoredOne() async throws {
        StubProtocol.responses = [(200, UsageDecodingTests.fixture)]
        let windows = try await makeClient(token: nil).validate(token: "pasted")
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(StubProtocol.seenAuthHeaders, ["Bearer pasted"])
    }

    func testValidateRejectsBadToken() async {
        StubProtocol.responses = [(401, Data())]
        do {
            _ = try await makeClient(token: nil).validate(token: "junk")
            XCTFail("should throw")
        } catch UsageClientError.unauthorized {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}
