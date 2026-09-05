import XCTest
@testable import SwiftTUI

/// The scrolling rule a pager needs: keep the anchor visible, move as little as
/// possible, and never scroll past the end.
final class TextPaneScrollTests: XCTestCase {

    private func offset(anchor: Int, from current: Int, height: Int = 10, count: Int = 100) -> Int {
        TextPane.scrollOffset(anchor: anchor, current: current, height: height, count: count)
    }

    func testAnchorAlreadyVisibleDoesNotScroll() {
        XCTAssertEqual(offset(anchor: 25, from: 20), 20)
        XCTAssertEqual(offset(anchor: 20, from: 20), 20, "the top row counts as visible")
        XCTAssertEqual(offset(anchor: 29, from: 20), 20, "and so does the bottom one")
    }

    func testScrollsJustEnoughGoingDown() {
        // One past the bottom moves by exactly one row, not half a screen.
        XCTAssertEqual(offset(anchor: 30, from: 20), 21)
        XCTAssertEqual(offset(anchor: 31, from: 20), 22)
    }

    func testScrollsJustEnoughGoingUp() {
        XCTAssertEqual(offset(anchor: 19, from: 20), 19)
        XCTAssertEqual(offset(anchor: 0, from: 20), 0)
    }

    /// A jump to the far end should land, not creep.
    func testLongJumpLandsInOneStep() {
        XCTAssertEqual(offset(anchor: 99, from: 0), 90)
        XCTAssertEqual(offset(anchor: 0, from: 90), 0)
    }

    func testNeverScrollsPastTheEnd() {
        XCTAssertEqual(offset(anchor: 99, from: 95), 90)
        XCTAssertLessThanOrEqual(offset(anchor: 99, from: 0), 90)
    }

    /// Content shorter than the pane has nothing to scroll, whatever the
    /// anchor or the previous offset say.
    func testShortContentStaysAtTheTop() {
        XCTAssertEqual(offset(anchor: 3, from: 0, height: 10, count: 5), 0)
        XCTAssertEqual(offset(anchor: 3, from: 4, height: 10, count: 5), 0)
        XCTAssertEqual(offset(anchor: 0, from: 0, height: 10, count: 10), 0,
                       "exactly full is still not scrollable")
    }

    /// Layout can propose zero rows while a window is being resized; the old
    /// hardcoded window would have produced a negative offset here.
    func testDegenerateSizesAreSafe() {
        XCTAssertEqual(offset(anchor: 5, from: 0, height: 0, count: 100), 0)
        XCTAssertEqual(offset(anchor: 0, from: 0, height: 10, count: 0), 0)
    }

    /// A pane that shrinks under the current offset must pull back, not leave
    /// the anchor stranded below the fold.
    func testShrinkingThePaneKeepsTheAnchorVisible() {
        let tall = offset(anchor: 50, from: 45, height: 20, count: 100)
        XCTAssertEqual(tall, 45)
        let short = offset(anchor: 50, from: 45, height: 3, count: 100)
        XCTAssertEqual(short, 48)
        XCTAssertTrue((short..<(short + 3)).contains(50))
    }
}

final class TextPaneViewportTests: XCTestCase {

    func testViewportStartsAtZeroAndIsWritable() {
        let viewport = TextPane.Viewport()
        XCTAssertEqual(viewport.height, 0)
        viewport.height = 24
        XCTAssertEqual(viewport.height, 24)
    }
}
