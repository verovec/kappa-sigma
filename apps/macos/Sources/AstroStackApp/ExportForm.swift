package import Foundation
package import ProcessKit
internal import RenderKit
package import SwiftUI

/// What the next export writes (`ExportSettings`): the files and formats, the star colour, the
/// export-only crop and mirror, the file names and the folder — every value the one applied.
package struct ExportForm: View {
  @Bindable var model: ExportStageModel
  @Environment(\.locale) private var locale

  /// The form of the next export of `model`.
  package init(model: ExportStageModel) {
    self.model = model
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      files
      formats
      values
      folder
      ExportTargetsForm(model: model)
    }
  }

  /// The deliverables; those that need a starless while there is none are greyed.
  @ViewBuilder private var files: some View {
    Text(.app("Files")).font(.headline)
    ForEach(ExportSettings.Deliverable.allCases, id: \.self) { deliverable in
      let unavailable = model.unavailableDeliverables.contains(deliverable)
      Toggle(isOn: chosen(deliverable)) { Text(Self.title(deliverable)) }
        .disabled(unavailable)
        .help(unavailable ? Text(.app("Needs the starless: separate the stars first.")) : Text(""))
        .accessible(
          .stageControl("export", "file." + deliverable.rawValue), label: Self.title(deliverable))
    }
  }

  @ViewBuilder private var formats: some View {
    Text(.app("Formats")).font(.headline)
    ForEach(ExportSettings.Format.allCases, id: \.self) { format in
      Toggle(isOn: chosen(format)) { Text(Self.title(format)) }
        .accessible(
          .stageControl("export", "format." + format.rawValue), label: Self.title(format))
    }
  }

  /// The star colour, the export-only crop and mirror, the file names.
  @ViewBuilder private var values: some View {
    ParameterRow(
      .app("Star colour"), parameter: number(\.starColour, default: 0.25, range: 0...1),
      key: "export.starColour", frozen: !model.hasStarless,
      format: { AstroFormat(locale: locale).parameter($0) },
      parse: { AstroFormat(locale: locale).parameter(parsing: $0) })
    ParameterRow(
      .app("Crop on each edge"), parameter: number(\.cropFraction, default: 0, range: 0...0.45),
      key: "export.crop", format: { AstroFormat(locale: locale).parameter($0) },
      parse: { AstroFormat(locale: locale).parameter(parsing: $0) })
    Picker(.app("Mirror"), selection: $model.settings.orientation) {
      ForEach(ExportSettings.Orientation.allCases, id: \.self) { orientation in
        Text(Self.title(orientation)).tag(orientation)
      }
    }
    .accessible(.stageControl("export", "mirror"), label: .app("Mirror"))
    TextField(.app("File name"), text: $model.settings.nameTemplate)
      .accessible(.stageControl("export", "name"), label: .app("File name"))
    Text(.app("{name} stands for final, final-starless, final-75-stars…"))
      .font(.caption).foregroundStyle(.secondary)
  }

  /// The base (with `~`), « Choose… » for this export, « Remember as default », the sub-path
  /// template and the folder it resolves to: the path shown is the one written (R2).
  private var folder: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      Text(.app("Folder")).font(.headline)
      HStack {
        Text(verbatim: Self.shown(model.base)).font(.caption).textSelection(.enabled)
          .lineLimit(1).truncationMode(.middle)
        Spacer()
        Button(.app("Choose…")) { chooseBase() }
          .accessible(.stageControl("export", "folder"), label: .app("Choose…"))
      }
      Toggle(isOn: $model.remember) { Text(.app("Remember as default")) }
        .accessible(.stageControl("export", "folder.remember"), label: .app("Remember as default"))
      TextField(.app("Sub-folders"), text: $model.template)
        .accessible(.stageControl("export", "folder.template"), label: .app("Sub-folders"))
      Text(.app("Tokens: \(ExportPathTemplate.listed)"))
        .font(.caption).foregroundStyle(.secondary)
      if !model.local {
        // Shown = written (R2): nothing stays in this folder when the copy goes to S3 only.
        Text(.app("Not kept on this Mac: written to a scratch folder, uploaded, then removed."))
          .font(.caption).foregroundStyle(.secondary)
      } else if let resolved = Self.resolved(model) {
        Text(verbatim: resolved).font(.caption).textSelection(.enabled)
          .lineLimit(2).truncationMode(.middle)
      } else if let refusal = model.folderRefusal {
        Text(UserFacingError.exportTemplate(refusal).message)
          .font(.caption).foregroundStyle(DesignColor.statusError.color)
      }
    }
  }

  /// `url` as the form shows it: `~` for the home folder.
  package static func shown(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
  }

  /// The folder the next export writes, as shown; `nil` when the template names none.
  package static func resolved(_ model: ExportStageModel) -> String? {
    model.folder.map(shown)
  }

  private func chooseBase() {
    guard let url = FolderPanel.pick(FolderPanel.make(startingIn: model.base, canCreate: true))
    else { return }
    model.base = url
  }

  private func chosen(_ deliverable: ExportSettings.Deliverable) -> Binding<Bool> {
    Binding(
      get: { model.effectiveDeliverables.contains(deliverable) },
      set: { model.settings.choose(deliverable, $0) })
  }

  private func chosen(_ format: ExportSettings.Format) -> Binding<Bool> {
    Binding(
      get: { model.settings.formats.contains(format) },
      set: { model.settings.choose(format, $0) })
  }

  private func number(
    _ path: WritableKeyPath<ExportSettings, Double>, default value: Double,
    range: ClosedRange<Double>
  ) -> Binding<ParameterValue> {
    Binding(
      get: { ParameterValue(default: value, range: range, value: model.settings[keyPath: path]) },
      set: { model.settings[keyPath: path] = $0.value })
  }

  package static func title(_ deliverable: ExportSettings.Deliverable) -> LocalizedStringResource {
    switch deliverable {
    case .final: .app("Final image")
    case .starless: .app("Starless")
    case .stars75: .app("Stars at 75 %")
    case .stars50: .app("Stars at 50 %")
    case .stars25: .app("Stars at 25 %")
    }
  }

  package static func title(_ format: ExportSettings.Format) -> LocalizedStringResource {
    switch format {
    case .png16: .app("PNG 16-bit")
    case .tiff16: .app("TIFF 16-bit")
    case .fits32: .app("FITS 32-bit float")
    }
  }

  package static func title(_ orientation: ExportSettings.Orientation) -> LocalizedStringResource {
    switch orientation {
    case .none: .app("None")
    case .hflip: .app("Left ↔ right")
    case .vflip: .app("Top ↔ bottom")
    }
  }
}
