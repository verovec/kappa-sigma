import AstroStackApp
import Foundation
import StackKit
import SwiftUI
import Testing

extension ReviewPaneTests {
  @Test(
    "the primary action (double-click, Return) opens the row's light, once, and decides nothing",
    arguments: [FrameReviewViewModelTests.LaneKind.readOnly, .live])
  func testDoubleClick_opensFrame(_ kind: FrameReviewViewModelTests.LaneKind) {
    let review = kind.model(FrameReviewViewModelTests.frames())
    review.reject(1)
    let (rows, current, isLive) = (review.rows, review.current, review.isLive)
    let opened = Recorded<URL>()
    let table = FrameTable(review: review, selection: .constant(2), open: { opened.append($0) })

    table.openLight(of: [2])
    #expect(opened.all == [URL(fileURLWithPath: "/c/L/2.fits")])
    #expect(review.rows == rows && review.current == current && review.isLive == isLive)
    #expect(review.decision == (kind == .live ? FrameDecision(exclude: [1]) : FrameDecision()))
  }

  @Test(
    "« Open in Viewer » is worded in fr and en, opens the same light, and is absent without a path",
    arguments: [("en", "Open in Viewer"), ("fr", "Ouvrir dans le visualiseur")])
  func testOpenInViewer_menu(_ language: String, _ title: String) {
    #expect(String(localized: FrameTable.openTitle(locale: Locale(identifier: language))) == title)
    var frames = FrameReviewViewModelTests.frames()
    frames.grades[2].path = ""
    let review = FrameReviewViewModel(frames: frames) { _ in }
    let opened = Recorded<URL>()
    let table = FrameTable(review: review, selection: .constant(nil), open: { opened.append($0) })

    #expect(table.light(of: [1]) == URL(fileURLWithPath: "/c/L/1.fits"), "the menu item exists")
    #expect(table.light(of: [3]) == nil, "no path: no menu item")
    #expect(table.light(of: []) == nil && table.light(of: [1, 2]) == nil, "one frame at a time")
    table.openLight(of: [3])
    table.openLight(of: [1, 2])
    #expect(opened.all.isEmpty)
    table.openLight(of: [1])
    #expect(opened.all == [URL(fileURLWithPath: "/c/L/1.fits")])
  }
}
