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
    func makeClient(tokens: [String]) -> ClaudeUsageClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        var remaining = tokens
        return ClaudeUsageClient(session: URLSession(configuration: config)) {
            remaining.isEmpty ? tokens.last! : remaining.removeFirst()
        }
    }

    override func setUp() {
        StubProtocol.responses = []
        StubProtocol.seenAuthHeaders = []
    }

    func testFetchParsesWindows() async throws {
        StubProtocol.responses = [(200, UsageDecodingTests.fixture)]
        let windows = try await makeClient(tokens: ["tok1"]).fetchUsage()
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(StubProtocol.seenAuthHeaders, ["Bearer tok1"])
    }

    func testRetriesOnceOn401WithFreshToken() async throws {
        StubProtocol.responses = [(401, Data()), (200, UsageDecodingTests.fixture)]
        let windows = try await makeClient(tokens: ["stale", "fresh"]).fetchUsage()
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(StubProtocol.seenAuthHeaders, ["Bearer stale", "Bearer fresh"])
    }

    func testThrowsUnauthorizedAfterSecond401() async {
        StubProtocol.responses = [(401, Data()), (401, Data())]
        do {
            _ = try await makeClient(tokens: ["a", "b"]).fetchUsage()
            XCTFail("should throw")
        } catch let e as UsageClientError {
            guard case .unauthorized = e else { return XCTFail("wrong error \(e)") }
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}
