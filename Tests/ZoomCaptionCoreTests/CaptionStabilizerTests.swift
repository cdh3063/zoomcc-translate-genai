import XCTest
@testable import ZoomCaptionCore

final class CaptionStabilizerTests: XCTestCase {
    func testNormalizerCollapsesWhitespaceAcrossLines() {
        let normalizer = CaptionNormalizer()

        XCTAssertEqual(
            normalizer.normalize("  hello   world\n\n from   zoom  "),
            "hello world from zoom"
        )
    }

    func testEmitsOnlyAfterTextIsStable() {
        let stabilizer = CaptionStabilizer(stableAfter: 1)
        let start = Date(timeIntervalSince1970: 100)

        XCTAssertNil(stabilizer.update("hello   world", now: start))
        XCTAssertNil(stabilizer.update("hello world", now: start.addingTimeInterval(0.5)))
        XCTAssertEqual(stabilizer.update("hello world", now: start.addingTimeInterval(1.1)), "hello world")
        XCTAssertNil(stabilizer.update("hello world", now: start.addingTimeInterval(2)))
    }

    func testNewTextResetsStabilityTimer() {
        let stabilizer = CaptionStabilizer(stableAfter: 1)
        let start = Date(timeIntervalSince1970: 100)

        XCTAssertNil(stabilizer.update("first caption", now: start))
        XCTAssertNil(stabilizer.update("second caption", now: start.addingTimeInterval(0.5)))
        XCTAssertNil(stabilizer.update("second caption", now: start.addingTimeInterval(1.0)))
        XCTAssertEqual(stabilizer.update("second caption", now: start.addingTimeInterval(1.6)), "second caption")
    }
}
