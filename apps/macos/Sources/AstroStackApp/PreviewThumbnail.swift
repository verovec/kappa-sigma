internal import AppKit
internal import Foundation
internal import RenderKit
internal import SwiftUI

/// A stage's quick look, read once per revision off the main actor: the panel's body runs on
/// every journal line.
struct PreviewThumbnail: View {
  let thumbnail: RunViewModel.Thumbnail
  @State private var image: NSImage?

  var body: some View {
    VStack(spacing: DesignMetrics.spacingXS) {
      Group {
        if let image {
          Image(nsImage: image).resizable().scaledToFit()
        } else {
          Image(systemName: "photo")
        }
      }
      .frame(height: 96)
      Text(verbatim: thumbnail.stage).font(.caption)
    }
    .task(id: thumbnail.revision) {
      image = await Self.read(thumbnail.url).flatMap(NSImage.init(data:))
    }
  }

  @concurrent
  private nonisolated static func read(_ url: URL) async -> Data? {
    try? Data(contentsOf: url)
  }
}
