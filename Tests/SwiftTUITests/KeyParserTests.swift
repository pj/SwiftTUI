import XCTest
@testable import SwiftTUI

final class KeyParserTests: XCTestCase {

    private func keys(_ input: String) -> [Application.Key] {
        var parser = KeyParser()
        var result: [Application.Key] = []
        for char in input { result += parser.parse(char) }
        return result
    }

    func testPlainCharactersPassThrough() {
        XCTAssertEqual(keys("abc"), [.character("a"), .character("b"), .character("c")])
    }

    func testNamedControlCharacters() {
        XCTAssertEqual(keys("\r"), [.enter])
        XCTAssertEqual(keys("\t"), [.tab])
        XCTAssertEqual(keys("\u{7f}"), [.backspace])
    }

    func testArrowsInBothEncodings() {
        XCTAssertEqual(keys("\u{1b}[A"), [.up])
        XCTAssertEqual(keys("\u{1b}[B"), [.down])
        // Terminals in application cursor mode send SS3 instead of CSI.
        XCTAssertEqual(keys("\u{1b}OC"), [.right])
        XCTAssertEqual(keys("\u{1b}OD"), [.left])
    }

    func testPagingAndHomeEnd() {
        XCTAssertEqual(keys("\u{1b}[5~"), [.pageUp])
        XCTAssertEqual(keys("\u{1b}[6~"), [.pageDown])
        XCTAssertEqual(keys("\u{1b}[H"), [.home])
        XCTAssertEqual(keys("\u{1b}[F"), [.end])
        XCTAssertEqual(keys("\u{1b}[4~"), [.end])
    }

    /// The reason this file exists. A bare Esc is indistinguishable from the
    /// start of a sequence by content, so it stays pending and is resolved by
    /// the silence that follows.
    func testLoneEscapeIsPendingUntilFlushed() {
        var parser = KeyParser()
        XCTAssertEqual(parser.parse("\u{1b}"), [])
        XCTAssertTrue(parser.isPending)

        // Too soon: still could be the start of a sequence.
        XCTAssertEqual(parser.flush(), [])

        Thread.sleep(forTimeInterval: KeyParser.escapeTimeout + 0.02)
        XCTAssertEqual(parser.flush(), [.escape])
        XCTAssertFalse(parser.isPending)
    }

    func testFlushAfterACompletedSequenceYieldsNothing() {
        var parser = KeyParser()
        for char in "\u{1b}[A" { _ = parser.parse(char) }
        Thread.sleep(forTimeInterval: KeyParser.escapeTimeout + 0.02)
        XCTAssertEqual(parser.flush(), [])
    }

    func testAltKeyIsEscapeThenTheKey() {
        XCTAssertEqual(keys("\u{1b}x"), [.escape, .character("x")])
    }

    /// An unbound function key must not leak its characters into the UI, which
    /// is what the previous parser did — pressing F5 typed "[15~".
    func testUnrecognisedSequenceIsReportedNotLeaked() {
        let result = keys("\u{1b}[15~")
        XCTAssertFalse(result.contains(.character("1")))
        XCTAssertFalse(result.contains(.character("~")))
    }

    /// Digits are CSI parameter bytes, so a run of them is a legitimately
    /// unfinished sequence, not garbage — it must stay pending, not guess.
    func testUnfinishedSequenceStaysPending() {
        var parser = KeyParser()
        var result: [Application.Key] = []
        for char in "\u{1b}[123456789" { result += parser.parse(char) }
        XCTAssertEqual(result, [])
        XCTAssertTrue(parser.isPending)

        // The final byte resolves it.
        XCTAssertEqual(parser.parse("~"), [.unknown])
        XCTAssertFalse(parser.isPending)
    }

    func testRunawaySequenceIsAbandoned() {
        var parser = KeyParser()
        var result: [Application.Key] = []
        for char in "\u{1b}[" + String(repeating: "1", count: 40) { result += parser.parse(char) }
        XCTAssertEqual(result, [.unknown])
        XCTAssertFalse(parser.isPending)
    }

    func testParserRecoversAfterAnUnknownSequence() {
        var parser = KeyParser()
        for char in "\u{1b}[15~" { _ = parser.parse(char) }
        XCTAssertEqual(parser.parse("a"), [.character("a")])
    }
}
