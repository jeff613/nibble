import XCTest
@testable import NibbleCore

final class ModelPaletteTests: XCTestCase {
    func testMapsModelIDsToFamilies() {
        XCTAssertEqual(ModelPalette.family(for: "claude-fable-5"), "fable")
        XCTAssertEqual(ModelPalette.family(for: "claude-opus-5"), "opus")
        XCTAssertEqual(ModelPalette.family(for: "claude-sonnet-5"), "sonnet")
        XCTAssertEqual(ModelPalette.family(for: "claude-haiku-4-5-20251001"), "haiku")
        XCTAssertEqual(ModelPalette.family(for: "claude-mythos-5"), "mythos")
    }

    func testUnknownModelsFallBackToOther() {
        XCTAssertEqual(ModelPalette.family(for: "gpt-5"), "other")
        XCTAssertEqual(ModelPalette.family(for: ""), "other")
        XCTAssertEqual(ModelPalette.family(for: "claude-something-new-7"), "other")
    }

    /// The requested assignments. Changing these changes the app's visual
    /// identity, so they're pinned rather than left to chart defaults.
    func testRequestedColoursArePinned() {
        XCTAssertEqual(ModelPalette.hex(for: "fable"), "E8833A")   // orange
        XCTAssertEqual(ModelPalette.hex(for: "opus"), "3B82F6")    // blue
        XCTAssertEqual(ModelPalette.hex(for: "sonnet"), "22A06B")  // green
    }

    func testEveryFamilyHasAColour() {
        for family in ModelPalette.families {
            XCTAssertFalse(ModelPalette.hex(for: family).isEmpty, "\(family) has no colour")
        }
    }

    func testColoursAreDistinct() {
        let colours = ModelPalette.families.map(ModelPalette.hex(for:))
        XCTAssertEqual(Set(colours).count, colours.count, "two families share a colour")
    }

    func testUnknownFamilyGetsTheOtherColour() {
        XCTAssertEqual(ModelPalette.hex(for: "not-a-family"), ModelPalette.hex(for: "other"))
    }

    // MARK: Stability — the actual bug this guards against

    func testFamilyColourDoesNotDependOnWhichOthersArePresent() {
        let soloWeek = ModelPalette.presentFamilies(in: ["claude-opus-5"])
        let busyWeek = ModelPalette.presentFamilies(
            in: ["claude-fable-5", "claude-opus-5", "claude-sonnet-5", "gpt-5"])

        XCTAssertEqual(soloWeek, ["opus"])
        XCTAssertEqual(busyWeek, ["fable", "opus", "sonnet", "other"])
        // Same colour in both, despite different positions in the domain.
        XCTAssertEqual(ModelPalette.hex(for: "opus"), "3B82F6")
    }

    func testPresentFamiliesFollowCanonicalOrderNotInputOrder() {
        let shuffled = ["claude-sonnet-5", "claude-fable-5", "claude-opus-5"]
        XCTAssertEqual(ModelPalette.presentFamilies(in: shuffled), ["fable", "opus", "sonnet"])
    }

    func testPresentFamiliesDeduplicates() {
        XCTAssertEqual(
            ModelPalette.presentFamilies(in: ["claude-opus-5", "claude-opus-4-8"]), ["opus"])
    }

    func testPresentFamiliesEmptyForNoData() {
        XCTAssertEqual(ModelPalette.presentFamilies(in: [String]()), [])
    }
}
