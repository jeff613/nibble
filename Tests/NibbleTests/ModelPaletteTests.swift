import XCTest
@testable import NibbleCore

final class ModelPaletteTests: XCTestCase {
    func testShortNameStripsVendorAndDatestamp() {
        XCTAssertEqual(ModelPalette.shortName(for: "claude-opus-5"), "opus-5")
        XCTAssertEqual(ModelPalette.shortName(for: "claude-sonnet-4-5-20251001"), "sonnet-4-5")
        XCTAssertEqual(ModelPalette.shortName(for: "grok-4.6-build"), "grok-4.6")
        XCTAssertEqual(ModelPalette.shortName(for: "gpt-5.6-sol"), "gpt-5.6-sol")
    }

    func testUnknownIdsStayDistinct() {
        let a = ModelPalette.shortName(for: "vendor-alpha-9")
        let b = ModelPalette.shortName(for: "vendor-beta-9")
        XCTAssertEqual(a, "vendor-alpha-9")
        XCTAssertEqual(b, "vendor-beta-9")
        XCTAssertNotEqual(ModelPalette.hex(for: a), ModelPalette.hex(for: b))
    }

    func testVersionedOpusModelsHaveDistinctColours() {
        XCTAssertEqual(ModelPalette.hex(for: ModelPalette.shortName(for: "claude-opus-5")), "3B82F6")
        XCTAssertEqual(ModelPalette.hex(for: "opus-4-8"), "8B5CF6")
    }

    func testCommonChartModelsHaveDistinctColours() {
        let names = ["fable-5", "opus-5", "opus-4-8", "sonnet-5", "gpt-5.6-sol", "grok-4.6"]
        XCTAssertEqual(Set(names.map(ModelPalette.hex(for:))).count, names.count)
    }

    func testPresentOrdersClaudeThenGptThenGrok() {
        let ids = ["grok-4.6-build", "gpt-5.6-sol", "claude-opus-5", "claude-fable-5"]
        XCTAssertEqual(
            ModelPalette.present(in: ids),
            ["fable-5", "opus-5", "gpt-5.6-sol", "grok-4.6"])
    }

    func testRequestedColoursArePinned() {
        XCTAssertEqual(ModelPalette.hex(for: "fable-5"), "E8833A")
        XCTAssertEqual(ModelPalette.hex(for: "opus-5"), "3B82F6")
        XCTAssertEqual(ModelPalette.hex(for: "sonnet-5"), "22A06B")
        XCTAssertEqual(ModelPalette.hex(for: "gpt-5.6-sol"), "DC2626")
        XCTAssertEqual(ModelPalette.hex(for: "grok-4.6"), "06B6D4")
    }

    func testPresentDeduplicatesShortNames() {
        XCTAssertEqual(
            ModelPalette.present(in: ["claude-opus-5", "CLAUDE-OPUS-5"]),
            ["opus-5"])
    }

    func testPresentEmptyForNoData() {
        XCTAssertEqual(ModelPalette.present(in: [String]()), [])
    }

    func testFamilyStillMapsClaudeIds() {
        XCTAssertEqual(ModelPalette.family(for: "claude-fable-5"), "fable")
        XCTAssertEqual(ModelPalette.family(for: "claude-opus-5"), "opus")
        XCTAssertEqual(ModelPalette.family(for: "gpt-5"), "other")
    }
}
