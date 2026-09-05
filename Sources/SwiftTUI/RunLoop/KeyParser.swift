import Foundation

/// Turns a byte stream from the terminal into keys.
///
/// Replaces `ArrowKeyParser`, which recognised only the four arrows and had two
/// problems beyond that. It consumed a lone `Esc` waiting forever for the `[`
/// that never came, so the Escape key was invisible to applications; and any
/// sequence it did not recognise was silently dropped a character at a time,
/// which surfaces as stray letters appearing in the UI when you press an unbound
/// function key.
///
/// This one recognises the common CSI sequences, reports anything else as
/// `.unknown` rather than leaking its characters, and resolves a pending escape
/// on a timeout so `Esc` works as a key.
struct KeyParser {

    /// How long to wait for the rest of a sequence before deciding a lone `Esc`
    /// was really the Escape key. Terminals send the whole sequence in one
    /// write, so anything still incomplete after this was a bare press.
    static let escapeTimeout: TimeInterval = 0.05

    private var pending: [Character] = []
    private var pendingSince: Date?
    /// Set when a sequence is abandoned. Its remaining bytes still have to be
    /// eaten, or they arrive as text — which is the bug this parser replaced.
    private var discarding = false

    /// Feeds one character. Returns any keys it completed.
    mutating func parse(_ char: Character) -> [Application.Key] {
        if discarding {
            if Self.isFinalByte(char) { discarding = false }
            return []
        }
        if pending.isEmpty {
            guard char == "\u{1b}" else { return [key(for: char)] }
            pending = [char]
            pendingSince = Date()
            return []
        }

        pending.append(char)

        // Alt+key arrives as Esc followed by an ordinary key.
        if pending.count == 2, char != "[", char != "O" {
            let result = [Application.Key.escape, key(for: char)]
            reset()
            return result
        }

        // SS3: the byte after Esc O is the final one.
        if pending.count == 3, pending[1] == "O" {
            return [complete()]
        }

        // CSI: parameter and intermediate bytes, then a final byte in 0x40-0x7E.
        if pending.count >= 3, pending[1] == "[" {
            if Self.isFinalByte(char) { return [complete()] }
            // Runaway garbage. Give up on identifying it, but keep swallowing
            // until the sequence ends so its bytes are not delivered as text.
            if pending.count > 32 {
                reset()
                discarding = true
                return [.unknown]
            }
        }
        return []
    }

    /// Resolves a finished sequence to a key, or `.unknown` if unrecognised.
    private mutating func complete() -> Application.Key {
        let key = Self.sequences[String(pending)] ?? .unknown
        reset()
        return key
    }

    /// Call when input goes quiet. Resolves a lone `Esc` into the Escape key.
    mutating func flush() -> [Application.Key] {
        guard let since = pendingSince,
              Date().timeIntervalSince(since) >= Self.escapeTimeout
        else { return [] }
        let wasBareEscape = pending == ["\u{1b}"]
        reset()
        return wasBareEscape ? [.escape] : []
    }

    var isPending: Bool { !pending.isEmpty }

    /// A CSI sequence ends at the first byte in 0x40-0x7E.
    private static func isFinalByte(_ char: Character) -> Bool {
        guard let ascii = char.asciiValue else { return false }
        return (0x40...0x7E).contains(ascii)
    }

    private mutating func reset() {
        pending = []
        pendingSince = nil
    }

    private func key(for char: Character) -> Application.Key {
        switch char {
        case "\r", "\n": return .enter
        case "\t": return .tab
        case ASCII.DEL, "\u{08}": return .backspace
        default: return .character(char)
        }
    }

    private static let sequences: [String: Application.Key] = [
        "\u{1b}[A": .up, "\u{1b}[B": .down, "\u{1b}[C": .right, "\u{1b}[D": .left,
        "\u{1b}OA": .up, "\u{1b}OB": .down, "\u{1b}OC": .right, "\u{1b}OD": .left,
        "\u{1b}[H": .home, "\u{1b}[F": .end,
        "\u{1b}[1~": .home, "\u{1b}[4~": .end,
        "\u{1b}[7~": .home, "\u{1b}[8~": .end,
        "\u{1b}OH": .home, "\u{1b}OF": .end,
        "\u{1b}[5~": .pageUp, "\u{1b}[6~": .pageDown,
        "\u{1b}[3~": .delete,
        "\u{1b}[Z": .backTab,
    ]
}
