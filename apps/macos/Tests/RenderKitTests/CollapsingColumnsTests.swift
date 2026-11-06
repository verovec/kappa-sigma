import AppKit
import CoreGraphics
import SwiftUI
import RenderKit
import Testing

/// Card 0176: a row of columns fits whatever width it is given — collapsing columns go first, in
/// their order, then the others shrink to their minimum — so a split view's column never asks for
/// a minimum it cannot get (the layout loop of 29/10 and 06/11).
@Suite("CollapsingColumns — widths from the proposal alone")
struct CollapsingColumnsTests {
  /// The Studio's row: left, image, View panel (collapses), side.
  static let studio = [
    ColumnWidth(min: 200, ideal: 260, max: 260),
    ColumnWidth(min: 240, ideal: 480, max: .infinity),
    ColumnWidth(min: 281, ideal: 281, max: 281, collapseRank: 0),
    ColumnWidth(min: 260, ideal: 320, max: 320),
  ]

  /// Two collapsing columns: the lower rank goes first.
  static let ranked = [
    ColumnWidth(min: 100, ideal: 100, max: 100, collapseRank: 1),
    ColumnWidth(min: 100, ideal: 100, max: .infinity),
    ColumnWidth(min: 100, ideal: 100, max: 100, collapseRank: 0),
  ]

  static let fixed = ColumnWidth(min: 100, ideal: 100, max: 100)

  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let columns: [ColumnWidth]
    let available: CGFloat?
    let widths: [CGFloat]
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(
      name: "unspecified: every column at its ideal",
      columns: studio, available: nil, widths: [260, 480, 281, 320]),
    Case(
      name: "infinite: the flexible column takes it",
      columns: studio, available: .infinity, widths: [260, .infinity, 281, 320]),
    Case(
      name: "wide: the image takes what the ideals leave",
      columns: studio, available: 1600, widths: [260, 739, 281, 320]),
    Case(
      name: "exactly the ideals",
      columns: studio, available: 1341, widths: [260, 480, 281, 320]),
    Case(
      name: "between minimums and ideals: each grows by its share of the room",
      columns: studio, available: 1161, widths: [230, 360, 281, 290]),
    Case(
      name: "under every minimum: the View panel collapses",
      columns: studio, available: 880, widths: [230, 360, 0, 290]),
    Case(
      name: "under the fixed minimums: every fixed column at its minimum",
      columns: studio, available: 600, widths: [200, 240, 0, 260]),
    Case(
      name: "rank 0 collapses before rank 1",
      columns: ranked, available: 250, widths: [100, 150, 0]),
    Case(
      name: "both collapse when only the fixed one fits",
      columns: ranked, available: 150, widths: [0, 150, 0]),
    Case(
      name: "a column shown from zero still takes the room",
      columns: [ColumnWidth(min: 0, ideal: 0, max: .infinity), fixed], available: 300,
      widths: [200, 100]),
  ]

  @Test("widths for a proposed width", arguments: cases)
  func testColumnSizing_widths(_ row: Case) {
    #expect(ColumnSizing.widths(row.columns, in: row.available) == row.widths)
  }

  @Test("a finite proposal at or over the minimum is filled exactly, never exceeded")
  func testColumnSizing_widths_fillProposal() {
    for available in stride(from: 700, through: 2000, by: 37) {
      let widths = ColumnSizing.widths(Self.studio, in: CGFloat(available))
      let total = widths.reduce(0, +)
      #expect(abs(total - CGFloat(available)) < 0.001, "\(available): \(widths)")
      for (width, column) in zip(widths, Self.studio) where width > 0 {
        #expect(width >= column.min && width <= column.max, "\(available): \(widths)")
      }
    }
  }

  @Test("the minimum is the fixed columns' minimums; collapsing ones count for nothing")
  func testColumnSizing_minimum() {
    #expect(ColumnSizing.minimum(Self.studio) == 700)
    #expect(ColumnSizing.minimum(Self.ranked) == 100)
    #expect(ColumnSizing.widths(Self.studio, in: 0) == [200, 240, 0, 260])
  }
}

/// The layout hosted: its minimum is the declared one whatever the columns hold, and a collapsed
/// column leaves the accessibility tree.
@MainActor
@Suite("CollapsingColumns — hosted")
struct CollapsingColumnsHostedTests {
  /// The Studio-shaped row, each column a labelled control wider than its minimum.
  static var row: some View {
    CollapsingColumns {
      ForEach(Array(CollapsingColumnsTests.studio.enumerated()), id: \.offset) { index, width in
        Button("column \(index)") {}
          .frame(width: 400)
          .accessible(.viewer("column\(index)"), verbatim: "column \(index)")
          .column(width)
      }
    }
  }

  @Test("the hosted minimum is the declared one, not the content's")
  func testMinimum_isDeclared() {
    let size = NSHostingController(rootView: Self.row).sizeThatFits(in: .zero)
    #expect(size.width == ColumnSizing.minimum(CollapsingColumnsTests.studio))
  }

  @Test("a collapsed column is gone from the accessibility tree; shown, it is there")
  func testCollapsed_leavesAccessibility() {
    func ids(_ width: CGFloat) -> Set<String> {
      Set(HostedEntries.entries(of: Self.row, width: width, height: 300).map(\.id))
    }
    let panel = AccessibilityID.viewer("column2").rawValue
    #expect(ids(1400).contains(panel))
    let narrow = ids(900)
    #expect(!narrow.contains(panel), "\(narrow)")
    #expect(narrow.contains(AccessibilityID.viewer("column1").rawValue))
  }
}
