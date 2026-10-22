internal import ProcessKit
internal import RenderKit
package import SwiftUI

/// « Compare pipelines » (card 0088): every difference from a saved pipeline to the one shown,
/// step by step (`PipelineDiff.entries`), values in the view's language.
package struct PipelineDiffSheet: View {
  let model: PipelineSidebarModel
  let savedName: String
  let close: () -> Void
  @Environment(\.locale) private var locale

  /// The sheet comparing the saved pipeline `savedName` with the one `model` shows.
  ///
  /// `close` dismisses it.
  package init(model: PipelineSidebarModel, savedName: String, close: @escaping () -> Void) {
    self.model = model
    self.savedName = savedName
    self.close = close
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      Text(.app("Compared with \(savedName)")).font(.headline)
      switch Result(catching: { try model.differences(from: savedName) }) {
      case .success(let entries) where entries.isEmpty:
        Text(.app("The same pipeline."))
      case .success(let entries):
        ScrollView {
          VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
              Text(verbatim: line(entry)).font(.callout).monospacedDigit()
            }
          }
        }
      case .failure(let error):
        StatusBadge(.error, UserFacingError(error).message)
      }
      HStack {
        Spacer()
        Button(.app("Close")) { close() }
          .keyboardShortcut(.cancelAction)
          .accessible(.studioPipelineCompareClose, label: .app("Close"))
      }
    }
    .padding(DesignMetrics.spacingL)
    .frame(minWidth: 420, minHeight: 240)
  }

  /// « 3. Stretch — targetBackground: 0.25 → 0.2 », in the view's language.
  private func line(_ entry: PipelineDiff.Entry) -> String {
    let title = String(
      localized: ProcessKitResources.title(
        model.workspace.title(of: entry.processID), locale: locale))
    let change: String
    switch entry.change {
    case .param(let id, let left, let right):
      change = String(localized: .app("\(id): \(words(left)) to \(words(right))", locale: locale))
    case .mode(let left, let right):
      change = String(
        localized: .app("breakpoint: \(mode(left)) to \(mode(right))", locale: locale))
    case .locked(_, let right):
      change = String(
        localized: right ? .app("locked", locale: locale) : .app("unlocked", locale: locale))
    case .process(let left, _):
      change = String(localized: .app("replaces \(left)", locale: locale))
    case .added:
      change = String(localized: .app("added", locale: locale))
    case .removed:
      change = String(localized: .app("removed", locale: locale))
    }
    return "\(entry.step + 1). \(title): \(change)"
  }

  private func mode(_ mode: PipelineStep.Mode) -> String {
    String(localized: mode == .stop ? .app("stop", locale: locale) : .app("auto", locale: locale))
  }

  private func words(_ value: ParamValue?) -> String {
    switch value {
    case .none: "—"
    case .number(let number): LocaleNumber.decimal(number, locale: locale, maxFractionDigits: 4)
    case .flag(let flag):
      String(localized: flag ? .app("On", locale: locale) : .app("Off", locale: locale))
    case .choice(let option): option
    case .points(let points): String(localized: .app("\(points.count) points", locale: locale))
    }
  }
}
