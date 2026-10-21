internal import RenderKit
package import StackKit
package import SwiftUI

/// Where an Import scan is: the phase in words, the files read so far, and a way to stop it.
///
/// Full size while the first scan of a folder runs (nothing else to show), compact in the header
/// when a rescan runs over a plan that stays visible.
package struct ImportScanProgressView: View {
  var progress: ScanProgress?
  var compact: Bool
  var onCancel: () -> Void
  @Environment(\.locale) private var locale

  /// The view of `progress` (`nil`: the scan has not reported yet); `onCancel` stops the scan.
  package init(progress: ScanProgress?, compact: Bool = false, onCancel: @escaping () -> Void) {
    self.progress = progress
    self.compact = compact
    self.onCancel = onCancel
  }

  package var body: some View {
    if compact {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text(phase).font(.callout).foregroundStyle(.secondary)
        if let count { Text(verbatim: count).font(.callout.monospacedDigit()) }
        Button(.app("Cancel Scan"), action: onCancel).controlSize(.small)
      }
    } else {
      VStack(spacing: 12) {
        Spacer()
        Text(phase).font(.title3)
        bar.frame(maxWidth: 420)
        if let count { Text(verbatim: count).font(.body.monospacedDigit()) }
        Text(.app("The capture is read, never written.")).font(.caption)
          .foregroundStyle(.secondary)
        Button(.app("Cancel Scan"), action: onCancel)
        Spacer()
      }
      .frame(maxWidth: .infinity)
    }
  }

  /// Determinate while files are read, indeterminate otherwise.
  @ViewBuilder
  private var bar: some View {
    if case .reading(let done, let total) = progress, total > 0 {
      ProgressView(value: Double(done), total: Double(total))
    } else {
      ProgressView().progressViewStyle(.linear)
    }
  }

  private var phase: LocalizedStringResource {
    switch progress {
    case nil: .app("Scanning…")
    case .library: .app("Indexing the calibration library…")
    case .reading: .app("Reading the FITS headers…")
    case .classifying: .app("Sorting the frames into sets…")
    }
  }

  private var count: String? {
    guard case .reading(let done, let total) = progress else { return nil }
    return AstroFormat(locale: locale).filesRead(done, of: total)
  }
}
