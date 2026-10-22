internal import AppKit
internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The blink panel (card 0069): the frame shown, read off the main actor per frame, its caption,
/// Previous / Next (⌘← / ⌘→ through the View menu) and Keep / Reject for that frame.
struct FrameBlinkView: View {
  var review: FrameReviewViewModel
  @State private var image: NSImage?
  @Environment(\.locale) private var locale

  var body: some View {
    let row = review.currentRow
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      Group {
        if let image {
          Image(nsImage: image).resizable().scaledToFit()
        } else {
          Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 180)
      .background(DesignColor.plotBackground.color)
      .task(id: row?.thumbnail) {
        image = await Self.read(row?.thumbnail).flatMap(NSImage.init(data:))
      }
      caption(row)
      controls(row).disabled(review.blinkRows.isEmpty)
    }
  }

  /// Previous / Next, then Keep / Reject of the frame shown.
  private func controls(_ row: FrameReviewViewModel.Row?) -> some View {
    HStack(spacing: DesignMetrics.spacingS) {
      Button {
        review.blinkPrevious()
      } label: {
        Image(systemName: "chevron.left")
      }
      .accessible(.reviewBlinkPrevious, label: .app("Previous Frame"))
      Button {
        review.blinkNext()
      } label: {
        Image(systemName: "chevron.right")
      }
      .accessible(.reviewBlinkNext, label: .app("Next Frame"))
      Spacer()
      if let row, row.isRegistered {
        Button(.app("Keep")) { review.keep(row.index) }
          .disabled(row.isKept)
          .accessible(.reviewBlinkKeep(row.index), label: .app("Keep Frame"))
        Button(.app("Reject")) { review.reject(row.index) }
          .disabled(!row.isKept)
          .accessible(.reviewBlinkReject(row.index), label: .app("Reject Frame"))
      }
    }
  }

  /// Frame number, night, FWHM and stars; what to do when nothing is shown.
  @ViewBuilder private func caption(_ row: FrameReviewViewModel.Row?) -> some View {
    if let row {
      let format = AstroFormat(locale: locale)
      let frame = format.integer(row.index)
      let night = row.night.isEmpty ? "—" : row.night
      let fwhm = format.fwhm(px: row.fwhm)
      let stars = format.integer(row.starCount)
      Text(.app("Frame \(frame) · \(night) · FWHM \(fwhm) · \(stars) stars"))
        .font(DesignMetrics.captionFont)
    } else {
      Text(.app("Choose a frame in the table to see it.")).font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @concurrent
  private nonisolated static func read(_ url: URL?) async -> Data? {
    guard let url else { return nil }
    return try? Data(contentsOf: url)
  }
}
