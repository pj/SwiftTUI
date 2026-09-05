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

    /// The pane's measured size, written during layout.
    ///
    /// A view learns how big it is only during layout, by which time the caller
    /// has already decided what to draw. Handing the pane a box to write into
    /// closes that loop without a second render pass: the caller reads it when
    /// it handles a key, not while laying out. Without it, anything sized in
    /// rows — a page-down, a jump to the bottom — has to guess.
    public final class Viewport {
        public var height: Int
        public var width: Int

        public init(height: Int = 0, width: Int = 0) {
            self.height = height
            self.width = width
        }
    }

    private let lines: [Line]
    private let offset: Int
    private let anchor: Int?
    private let columnOffset: Int
    private let viewport: Viewport?

    public init(
        lines: [Line],
        offset: Int = 0,
        columnOffset: Int = 0,
        viewport: Viewport? = nil
    ) {
        self.init(
            lines: lines, offset: offset, anchor: nil,
            columnOffset: columnOffset, viewport: viewport)
    }

    /// Scrolls to keep `anchor` on screen, moving as little as it can.
    ///
    /// The caller cannot do this itself: how many rows a pane has is settled
    /// during layout, and guessing it means the selection vanishes on a short
    /// terminal and the view scrolls early on a tall one.
    public init(
        lines: [Line],
        keeping anchor: Int,
        columnOffset: Int = 0,
        viewport: Viewport? = nil
    ) {
        self.init(
            lines: lines, offset: 0, anchor: anchor,
            columnOffset: columnOffset, viewport: viewport)
    }

    private init(
        lines: [Line],
        offset: Int,
        anchor: Int?,
        columnOffset: Int,
        viewport: Viewport?
    ) {
        self.lines = lines
        self.offset = offset
        self.anchor = anchor
        self.columnOffset = columnOffset
        self.viewport = viewport
    }

    /// Where a pane of `height` rows should start so that `anchor` is visible,
    /// given that it currently starts at `current`.
    ///
    /// It scrolls by the minimum needed rather than re-centring: re-centring on
    /// every move makes the whole view slide under a held key, which is both
    /// disorienting and much more to redraw.
    public static func scrollOffset(
        anchor: Int, current: Int, height: Int, count: Int
    ) -> Int {
        guard height > 0, count > height else { return 0 }
        var offset = current
        if anchor < offset {
            offset = anchor
        } else if anchor >= offset + height {
            offset = anchor - height + 1
        }
        return min(max(offset, 0), count - height)
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.control = TextPaneControl(
            lines: lines, offset: offset, anchor: anchor,
            columnOffset: columnOffset, viewport: viewport)
    }

    func updateNode(_ node: Node) {
        node.view = self
        let control = node.control as! TextPaneControl
        control.set(
            lines: lines, offset: offset, anchor: anchor,
            columnOffset: columnOffset, viewport: viewport)
        control.layer.invalidate()
    }

    private class TextPaneControl: Control {
        private var lines: [Line]
        private var offset: Int
        private var anchor: Int?
        private var columnOffset: Int
        private var viewport: Viewport?

        /// Where the pane currently starts. Kept across updates so anchored
        /// scrolling can move by the minimum, rather than recomputing from
        /// scratch and jumping.
        private var scrollOffset = 0

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

        init(
            lines: [Line], offset: Int, anchor: Int?,
            columnOffset: Int, viewport: Viewport?
        ) {
            self.lines = lines
            self.offset = offset
            self.anchor = anchor
            self.columnOffset = columnOffset
            self.viewport = viewport
            self.scrollOffset = offset
        }

        func set(
            lines: [Line], offset: Int, anchor: Int?,
            columnOffset: Int, viewport: Viewport?
        ) {
            self.lines = lines
            self.offset = offset
            self.anchor = anchor
            self.columnOffset = columnOffset
            self.viewport = viewport
            cache = [:]
        }

        override func size(proposedSize: Size) -> Size { proposedSize }

        override func layout(size: Size) {
            super.layout(size: size)
            let height = size.height.intValue
            viewport?.height = height
            viewport?.width = size.width.intValue

            // Resolved here rather than in cell(at:) so every cell of a frame
            // is drawn against the same offset.
            if let anchor {
                scrollOffset = TextPane.scrollOffset(
                    anchor: anchor, current: scrollOffset,
                    height: height, count: lines.count)
            } else {
                scrollOffset = offset
            }
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
            let index = scrollOffset + position.line.intValue
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
