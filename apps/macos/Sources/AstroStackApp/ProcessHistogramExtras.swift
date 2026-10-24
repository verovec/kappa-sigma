internal import ProcessKit
internal import RenderKit
internal import SwiftUI

/// The panel's histogram (card 0089): the head's values — the process's input, said in a caption
/// (card 0128) — with the process's handles over them when its values sit there, a drag setting
/// the value it names; for the levels, what each channel sends to black and to white (measured
/// on the head, shown only).
struct ProcessHistogramExtras: View {
  let model: ProcessPanelModel
  let sample: HeadSample
  @Environment(\.locale) private var locale

  var body: some View {
    let handles = model.handles
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      Text(Self.caption).font(.caption).foregroundStyle(.secondary)
      HistogramHandles(
        bins: sample.bins, handles: handles.isEmpty ? nil : handles, key: model.histogramKey,
        label: .app("Input histogram"),
        hint: handles.isEmpty ? Self.caption : .app("Drag a handle to set the value it names")
      ) { channel, handle, position in
        model.drag(handle, channel: channel, to: position)
      }
      .frame(height: 110)
      ForEach(Array(model.clipping.enumerated()), id: \.offset) { channel, clipping in
        let (low, high) = (format.share(clipping.low), format.share(clipping.high))
        Text(.app("\(name(channel)): \(low) to black, \(high) to white"))
          .font(.caption)
          .monospacedDigit()
      }
    }
  }

  /// The visible title: which image the plot counts (the viewer's may count a preview).
  static let caption: LocalizedStringResource = .app("Input — the head before this process")

  private var format: AstroFormat { AstroFormat(locale: locale) }

  private func name(_ channel: Int) -> String {
    guard sample.planes.count == 3 else {
      return String(localized: .app("Luminance", locale: locale))
    }
    return String(
      localized: [
        .app("Red", locale: locale), .app("Green", locale: locale), .app("Blue", locale: locale),
      ][channel])
  }
}
