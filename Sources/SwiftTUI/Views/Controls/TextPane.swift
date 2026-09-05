import Foundation

/// A scrollable block of pre-styled lines that fills the space offered to it.
///
/// `ScrollView` cannot do this. It scrolls only to bring a *focused control*
/// into view, so showing a long document means making every line focusable —
/// which is both slow and the wrong focus semantics. This takes an explicit
/// offset instead, the way a pager does.
///
/// It also exists here rather than in an application because `Control`, `Cell`
/// and `Position` are all internal to SwiftTUI: a custom primitive view cannot
/// be written from outside the module.
public struct TextPane: View, PrimitiveView {

    /// One styled line. Styling is per line rather than per run, which is all a
    /// JSON viewer needs and keeps the cell lookup a simple index.
    public struct Line {
        public var text: String
        public var color: Color
        public var bold: Bool
        public var highlighted: Bool

        public init(
            _ text: String,
            color: Color = .default,
            bold: Bool = false,
            highlighted: Bool = false
        ) {
            self.text = text
            self.color = color
            self.bold = bold
            self.highlighted = highlighted
        }
    }

    private let lines: [Line]
    private let offset: Int

    public init(lines: [Line], offset: Int = 0) {
        self.lines = lines
        self.offset = offset
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.control = TextPaneControl(lines: lines, offset: offset)
    }

    func updateNode(_ node: Node) {
        node.view = self
        let control = node.control as! TextPaneControl
        control.lines = lines
        control.offset = offset
        control.layer.invalidate()
    }

    private class TextPaneControl: Control {
        var lines: [Line]
        var offset: Int

        /// Characters are cached per line so `cell(at:)` — called once per
        /// visible cell, every frame — is an array index rather than a repeated
        /// walk of a String's grapheme clusters.
        private var cache: [Int: [Character]] = [:]

        init(lines: [Line], offset: Int) {
            self.lines = lines
            self.offset = offset
        }

        override func size(proposedSize: Size) -> Size { proposedSize }

        override func layout(size: Size) {
            super.layout(size: size)
            cache = [:]
        }

        override func cell(at position: Position) -> Cell? {
            let index = offset + position.line.intValue
            guard index >= 0, index < lines.count else { return .init(char: " ") }
            let line = lines[index]

            let characters: [Character]
            if let cached = cache[index] {
                characters = cached
            } else {
                characters = Array(line.text)
                cache[index] = characters
            }

            let column = position.column.intValue
            let char: Character = column < characters.count ? characters[column] : " "

            var attributes = CellAttributes()
            attributes.bold = line.bold
            attributes.inverted = line.highlighted
            return Cell(
                char: char, foregroundColor: line.color, attributes: attributes)
        }
    }
}
