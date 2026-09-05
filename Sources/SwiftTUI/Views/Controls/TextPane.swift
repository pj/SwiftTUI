import Foundation

/// A scrollable block of styled text that fills the space offered to it.
///
/// `ScrollView` cannot do this. It scrolls only to bring a *focused control*
/// into view, so showing a long document means making every line focusable —
/// both slow and the wrong focus semantics. This takes explicit offsets, the way
/// a pager does, and scrolls in both axes.
///
/// It lives inside the module because `Control`, `Cell` and `Position` are all
/// internal: a custom primitive view cannot be written from outside the package.
public struct TextPane: View, PrimitiveView {

    /// A styled run within a line. Lines are built from spans rather than
    /// carrying one colour so that syntax highlighting can colour a key
    /// differently from its value.
    public struct Span {
        public var text: String
        public var color: Color
        public var bold: Bool
        public var background: Color?

        public init(
            _ text: String,
            color: Color = .default,
            bold: Bool = false,
            background: Color? = nil
        ) {
            self.text = text
            self.color = color
            self.bold = bold
            self.background = background
        }
    }

    public struct Line {
        public var spans: [Span]
        /// Drawn inverted, for the selected row or a changed value.
        public var highlighted: Bool

        public init(spans: [Span], highlighted: Bool = false) {
            self.spans = spans
            self.highlighted = highlighted
        }

        public init(
            _ text: String,
            color: Color = .default,
            bold: Bool = false,
            highlighted: Bool = false
        ) {
            self.init(
                spans: [Span(text, color: color, bold: bold)],
                highlighted: highlighted)
        }

        public var text: String { spans.map(\.text).joined() }
    }

    private let lines: [Line]
    private let offset: Int
    private let columnOffset: Int

    public init(lines: [Line], offset: Int = 0, columnOffset: Int = 0) {
        self.lines = lines
        self.offset = offset
        self.columnOffset = columnOffset
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.control = TextPaneControl(
            lines: lines, offset: offset, columnOffset: columnOffset)
    }

    func updateNode(_ node: Node) {
        node.view = self
        let control = node.control as! TextPaneControl
        control.set(lines: lines, offset: offset, columnOffset: columnOffset)
        control.layer.invalidate()
    }

    private class TextPaneControl: Control {
        private var lines: [Line]
        private var offset: Int
        private var columnOffset: Int

        /// One entry per character of a line, so `cell(at:)` — called for every
        /// visible cell on every frame — is an array index rather than a walk of
        /// spans and grapheme clusters.
        private struct Rendered {
            var characters: [Character]
            var colors: [Color]
            var bold: [Bool]
            var backgrounds: [Color?]
        }
        private var cache: [Int: Rendered] = [:]

        init(lines: [Line], offset: Int, columnOffset: Int) {
            self.lines = lines
            self.offset = offset
            self.columnOffset = columnOffset
        }

        func set(lines: [Line], offset: Int, columnOffset: Int) {
            self.lines = lines
            self.offset = offset
            self.columnOffset = columnOffset
            cache = [:]
        }

        override func size(proposedSize: Size) -> Size { proposedSize }

        override func layout(size: Size) {
            super.layout(size: size)
            cache = [:]
        }

        private func rendered(_ index: Int) -> Rendered {
            if let cached = cache[index] { return cached }
            var result = Rendered(characters: [], colors: [], bold: [], backgrounds: [])
            for span in lines[index].spans {
                for character in span.text {
                    result.characters.append(character)
                    result.colors.append(span.color)
                    result.bold.append(span.bold)
                    result.backgrounds.append(span.background)
                }
            }
            cache[index] = result
            return result
        }

        override func cell(at position: Position) -> Cell? {
            let index = offset + position.line.intValue
            guard index >= 0, index < lines.count else { return Cell(char: " ") }

            let line = lines[index]
            let row = rendered(index)
            let column = columnOffset + position.column.intValue

            var attributes = CellAttributes()
            attributes.inverted = line.highlighted

            guard column >= 0, column < row.characters.count else {
                // Past the end of the text: still paint, so a highlighted row
                // inverts for its full width instead of stopping at the text.
                return Cell(char: " ", attributes: attributes)
            }

            attributes.bold = row.bold[column]
            return Cell(
                char: row.characters[column],
                foregroundColor: row.colors[column],
                backgroundColor: row.backgrounds[column],
                attributes: attributes)
        }
    }
}
