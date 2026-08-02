import XCTest
@testable import UsageBarCore

final class TokenStoreTests: XCTestCase {
    // Each run uses a throwaway service name so tests never touch the real item.
    var store: TokenStore!

    override func setUp() {
        store = TokenStore(service: "UsageBarTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? store.delete()
    }

    func testLoadReturnsNilWhenUnset() {
        XCTAssertNil(store.load())
    }

    func testSaveThenLoadRoundTrips() throws {
        try store.save("sk-ant-oat01-example")
        XCTAssertEqual(store.load(), "sk-ant-oat01-example")
    }

    func testSaveOverwritesExisting() throws {
        try store.save("first")
        try store.save("second")
        XCTAssertEqual(store.load(), "second")
    }

    func testDeleteRemovesToken() throws {
        try store.save("something")
        try store.delete()
        XCTAssertNil(store.load())
    }

    func testDeleteIsIdempotent() {
        XCTAssertNoThrow(try store.delete())
    }

    func testTrimsWhitespaceOnSave() throws {
        try store.save("  sk-ant-oat01-padded\n")
        XCTAssertEqual(store.load(), "sk-ant-oat01-padded")
    }

    func testRejectsEmptyToken() {
        XCTAssertThrowsError(try store.save("   "))
    }
}
