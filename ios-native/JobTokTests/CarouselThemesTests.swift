import XCTest
@testable import JobTok

final class CarouselThemesTests: XCTestCase {
    // The backend can add theme ids at any time; an unknown id must fall
    // back instead of crashing the feed.
    func testUnknownThemeFallsBackToSlateGradient() {
        let resolved = CarouselTheme.resolve("theme-from-the-future")
        XCTAssertEqual(resolved.id, CarouselTheme.slateGradient.id)
    }

    func testKnownThemeResolves() {
        let resolved = CarouselTheme.resolve("slate-gradient")
        XCTAssertEqual(resolved.id, "slate-gradient")
    }
}
