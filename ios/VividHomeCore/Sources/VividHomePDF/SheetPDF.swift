// Lifting a drawing out of a PDF (ADR-0032).
//
// Everything here needs Apple's PDF frameworks, so the file compiles to
// nothing on Linux. It is kept as thin as it can be: it walks the page and
// hands the core package plain numbers, and every decision about what those
// numbers mean is made there, where Linux CI can test it.

#if canImport(PDFKit) && canImport(CoreGraphics)
  import CoreGraphics
  import Foundation
  import PDFKit
  import VividHomeCore

  public enum SheetPDF {
    /// The page as a ``Sheet``, or nil when it cannot be read this way: no
    /// such page, or one stored rotated, which the plan raster does not
    /// handle either.
    public static func sheet(data: Data, page index: Int) -> Sheet? {
      guard let document = PDFDocument(data: data), let page = document.page(at: index) else {
        return nil
      }
      return sheet(page: page)
    }

    public static func sheet(page: PDFPage) -> Sheet? {
      guard page.rotation % 360 == 0, let reference = page.pageRef else { return nil }
      let box = page.bounds(for: .mediaBox)
      guard box.width > 0, box.height > 0 else { return nil }

      // Page space has its origin at the bottom-left and y up; a sheet has it
      // at the top-left and y down, like the raster the plan is stored as.
      func point(_ p: CGPoint) -> Sheet.Point {
        Sheet.Point(Double(p.x - box.minX), Double(box.maxY - p.y))
      }

      let walker = Walker()
      walker.walk(reference)

      let fills = walker.fills.map { fill in
        Sheet.Fill(
          polygons: fill.polygons.map { $0.map(point) },
          red: fill.red, green: fill.green, blue: fill.blue)
      }
      let segments = walker.segments.map { Sheet.Segment(point($0.0), point($0.1)) }
      return Sheet(
        width: Double(box.width), height: Double(box.height),
        glyphs: glyphs(of: page, in: box), fills: fills, segments: segments)
    }

    /// Every character with its box, in the page's reading order. Taken one
    /// selection at a time so a character and its bounds always come from the
    /// same place.
    static func glyphs(of page: PDFPage, in box: CGRect) -> [Sheet.Glyph] {
      var out: [Sheet.Glyph] = []
      let lineBreak = Sheet.Glyph(text: "\n", box: Sheet.Box(minX: 0, minY: 0, maxX: 0, maxY: 0))
      for index in 0..<page.numberOfCharacters {
        guard let selection = page.selection(for: NSRange(location: index, length: 1)),
          let text = selection.string, !text.isEmpty
        else {
          out.append(lineBreak)
          continue
        }
        let bounds = selection.bounds(for: page)
        let shown = text.filter { !$0.isNewline }
        if !shown.isEmpty {
          out.append(
            Sheet.Glyph(
              text: String(shown),
              box: Sheet.Box(
                minX: Double(bounds.minX - box.minX), minY: Double(box.maxY - bounds.maxY),
                maxX: Double(bounds.maxX - box.minX), maxY: Double(box.maxY - bounds.minY))))
        }
        if shown.count != text.count { out.append(lineBreak) }
      }
      return out
    }
  }

  /// Walks a page's drawing instructions, keeping what was filled and what
  /// was stroked, in page space.
  final class Walker {
    struct Painted {
      var polygons: [[CGPoint]]
      var red: Double
      var green: Double
      var blue: Double
    }

    struct State {
      var transform = CGAffineTransform.identity
      var red = 0.0
      var green = 0.0
      var blue = 0.0
    }

    var fills: [Painted] = []
    var segments: [(CGPoint, CGPoint)] = []

    var state = State()
    var saved: [State] = []
    /// The path being built: finished subpaths, and the one still open.
    var subpaths: [(points: [CGPoint], closed: Bool)] = []
    var open: [CGPoint] = []
    var depth = 0
    var table: CGPDFOperatorTableRef?

    /// A sheet with more lines than this is not one whose dimensions need
    /// every last stroke.
    static let segmentLimit = 600_000

    func walk(_ page: CGPDFPage) {
      guard let table = CGPDFOperatorTableCreate() else { return }
      self.table = table
      Walker.register(on: table)
      let stream = CGPDFContentStreamCreateWithPage(page)
      let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(self).toOpaque())
      CGPDFScannerScan(scanner)
      CGPDFScannerRelease(scanner)
      CGPDFContentStreamRelease(stream)
      CGPDFOperatorTableRelease(table)
      self.table = nil
    }

    // MARK: Path building

    func place(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: x, y: y).applying(state.transform)
    }

    func finishOpen(closed: Bool) {
      if open.count >= 2 { subpaths.append((open, closed)) }
      open = []
    }

    func move(_ x: CGFloat, _ y: CGFloat) {
      finishOpen(closed: false)
      open = [place(x, y)]
    }

    func line(_ x: CGFloat, _ y: CGFloat) {
      open.append(place(x, y))
    }

    func rectangle(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
      finishOpen(closed: false)
      subpaths.append(([place(x, y), place(x + w, y), place(x + w, y + h), place(x, y + h)], true))
    }

    func close() {
      let first = open.first
      finishOpen(closed: true)
      // A path may carry on from the point it closed at.
      if let first { open = [first] }
    }

    func paint(fill: Bool, stroke: Bool, closing: Bool) {
      if closing {
        finishOpen(closed: true)
      } else {
        finishOpen(closed: false)
      }
      if fill {
        let polygons = subpaths.map(\.points).filter { $0.count >= 3 }
        if !polygons.isEmpty {
          fills.append(Painted(polygons: polygons, red: state.red, green: state.green, blue: state.blue))
        }
      }
      if stroke, segments.count < Walker.segmentLimit {
        for subpath in subpaths {
          for index in 1..<subpath.points.count {
            segments.append((subpath.points[index - 1], subpath.points[index]))
          }
          if subpath.closed, subpath.points.count > 2, let first = subpath.points.first,
            let last = subpath.points.last
          {
            segments.append((last, first))
          }
        }
      }
      subpaths = []
      open = []
    }

    func setFill(_ components: [CGFloat]) {
      switch components.count {
      case 1:
        state.red = Double(components[0])
        state.green = Double(components[0])
        state.blue = Double(components[0])
      case 3:
        state.red = Double(components[0])
        state.green = Double(components[1])
        state.blue = Double(components[2])
      case 4:
        let black = 1 - Double(components[3])
        state.red = (1 - Double(components[0])) * black
        state.green = (1 - Double(components[1])) * black
        state.blue = (1 - Double(components[2])) * black
      default:
        // A pattern or a colour space this does not read: not a solid wall.
        state.red = 1
        state.green = 1
        state.blue = 1
      }
    }

    // MARK: Operators

    static func walker(_ info: UnsafeMutableRawPointer?) -> Walker? {
      info.map { Unmanaged<Walker>.fromOpaque($0).takeUnretainedValue() }
    }

    /// Pop `count` numbers, returned in the order they were written.
    static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
      var out: [CGFloat] = []
      for _ in 0..<count {
        var value: CGPDFReal = 0
        guard CGPDFScannerPopNumber(scanner, &value) else { return nil }
        out.append(value)
      }
      return out.reversed()
    }

    /// Pop every number waiting, in the order written.
    static func allNumbers(_ scanner: CGPDFScannerRef) -> [CGFloat] {
      var out: [CGFloat] = []
      var value: CGPDFReal = 0
      while out.count < 8, CGPDFScannerPopNumber(scanner, &value) { out.append(value) }
      return out.reversed()
    }

    static func register(on table: CGPDFOperatorTableRef) {
      CGPDFOperatorTableSetCallback(table, "q") { _, info in
        guard let walker = Walker.walker(info) else { return }
        walker.saved.append(walker.state)
      }
      CGPDFOperatorTableSetCallback(table, "Q") { _, info in
        guard let walker = Walker.walker(info), let state = walker.saved.popLast() else { return }
        walker.state = state
      }
      CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
        guard let walker = Walker.walker(info), let v = Walker.numbers(scanner, 6) else { return }
        let matrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
        walker.state.transform = matrix.concatenating(walker.state.transform)
      }

      CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
        guard let walker = Walker.walker(info), let v = Walker.numbers(scanner, 2) else { return }
        walker.move(v[0], v[1])
      }
      CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
        guard let walker = Walker.walker(info), let v = Walker.numbers(scanner, 2) else { return }
        walker.line(v[0], v[1])
      }
      // Curves are followed to where they end: a wall is not drawn with one,
      // and a door swing only has to not break the path it is part of.
      CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
        guard let walker = Walker.walker(info), let v = Walker.numbers(scanner, 6) else { return }
        walker.line(v[4], v[5])
      }
      CGPDFOperatorTableSetCallback(table, "v") { scanner, info in
        guard let walker = Walker.walker(info), let v = Walker.numbers(scanner, 4) else { return }
        walker.line(v[2], v[3])
      }
      CGPDFOperatorTableSetCallback(table, "y") { scanner, info in
        guard let walker = Walker.walker(info), let v = Walker.numbers(scanner, 4) else { return }
        walker.line(v[2], v[3])
      }
      CGPDFOperatorTableSetCallback(table, "h") { _, info in
        Walker.walker(info)?.close()
      }
      CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
        guard let walker = Walker.walker(info), let v = Walker.numbers(scanner, 4) else { return }
        walker.rectangle(v[0], v[1], v[2], v[3])
      }

      CGPDFOperatorTableSetCallback(table, "f") { _, info in
        Walker.walker(info)?.paint(fill: true, stroke: false, closing: false)
      }
      CGPDFOperatorTableSetCallback(table, "F") { _, info in
        Walker.walker(info)?.paint(fill: true, stroke: false, closing: false)
      }
      CGPDFOperatorTableSetCallback(table, "f*") { _, info in
        Walker.walker(info)?.paint(fill: true, stroke: false, closing: false)
      }
      CGPDFOperatorTableSetCallback(table, "B") { _, info in
        Walker.walker(info)?.paint(fill: true, stroke: true, closing: false)
      }
      CGPDFOperatorTableSetCallback(table, "B*") { _, info in
        Walker.walker(info)?.paint(fill: true, stroke: true, closing: false)
      }
      CGPDFOperatorTableSetCallback(table, "b") { _, info in
        Walker.walker(info)?.paint(fill: true, stroke: true, closing: true)
      }
      CGPDFOperatorTableSetCallback(table, "b*") { _, info in
        Walker.walker(info)?.paint(fill: true, stroke: true, closing: true)
      }
      CGPDFOperatorTableSetCallback(table, "S") { _, info in
        Walker.walker(info)?.paint(fill: false, stroke: true, closing: false)
      }
      CGPDFOperatorTableSetCallback(table, "s") { _, info in
        Walker.walker(info)?.paint(fill: false, stroke: true, closing: true)
      }
      CGPDFOperatorTableSetCallback(table, "n") { _, info in
        Walker.walker(info)?.paint(fill: false, stroke: false, closing: false)
      }

      CGPDFOperatorTableSetCallback(table, "g") { scanner, info in
        guard let walker = Walker.walker(info), let v = Walker.numbers(scanner, 1) else { return }
        walker.setFill(v)
      }
      CGPDFOperatorTableSetCallback(table, "rg") { scanner, info in
        guard let walker = Walker.walker(info), let v = Walker.numbers(scanner, 3) else { return }
        walker.setFill(v)
      }
      CGPDFOperatorTableSetCallback(table, "k") { scanner, info in
        guard let walker = Walker.walker(info), let v = Walker.numbers(scanner, 4) else { return }
        walker.setFill(v)
      }
      CGPDFOperatorTableSetCallback(table, "sc") { scanner, info in
        guard let walker = Walker.walker(info) else { return }
        walker.setFill(Walker.allNumbers(scanner))
      }
      CGPDFOperatorTableSetCallback(table, "scn") { scanner, info in
        guard let walker = Walker.walker(info) else { return }
        // A pattern is named last; with one, whatever numbers come with it
        // are its tint, not a colour to read.
        var name: UnsafePointer<CChar>?
        if CGPDFScannerPopName(scanner, &name) {
          _ = Walker.allNumbers(scanner)
          walker.setFill([])
        } else {
          walker.setFill(Walker.allNumbers(scanner))
        }
      }

      CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
        guard let walker = Walker.walker(info) else { return }
        var name: UnsafePointer<CChar>?
        guard CGPDFScannerPopName(scanner, &name), let name else { return }
        walker.drawForm(named: name, from: scanner, info: info)
      }
    }

    /// A drawing inside the drawing: some exporters wrap the whole sheet, or
    /// each symbol, in one.
    func drawForm(named name: UnsafePointer<CChar>, from scanner: CGPDFScannerRef, info: UnsafeMutableRawPointer?) {
      guard depth < 8, let table else { return }
      let parent = CGPDFScannerGetContentStream(scanner)
      guard let object = CGPDFContentStreamGetResource(parent, "XObject", name) else { return }
      var found: CGPDFStreamRef?
      guard CGPDFObjectGetValue(object, .stream, &found), let stream = found,
        let dictionary = CGPDFStreamGetDictionary(stream)
      else { return }
      var subtype: UnsafePointer<CChar>?
      guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype,
        String(cString: subtype) == "Form"
      else { return }

      var matrix = CGAffineTransform.identity
      var array: CGPDFArrayRef?
      if CGPDFDictionaryGetArray(dictionary, "Matrix", &array), let array, CGPDFArrayGetCount(array) == 6 {
        var v = [CGPDFReal](repeating: 0, count: 6)
        var complete = true
        for index in 0..<6 where !CGPDFArrayGetNumber(array, index, &v[index]) { complete = false }
        if complete {
          matrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
        }
      }
      var resources: CGPDFDictionaryRef?
      _ = CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)

      saved.append(state)
      state.transform = matrix.concatenating(state.transform)
      depth += 1
      let content = CGPDFContentStreamCreateWithStream(stream, resources ?? dictionary, parent)
      let inner = CGPDFScannerCreate(content, table, info)
      CGPDFScannerScan(inner)
      CGPDFScannerRelease(inner)
      CGPDFContentStreamRelease(content)
      depth -= 1
      if let restored = saved.popLast() { state = restored }
    }
  }
#endif
