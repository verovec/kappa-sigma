internal import AppKit
internal import ProcessKit
internal import RenderKit
internal import SwiftUI

/// What the next export writes (`ExportSettings`): the files and formats, the star colour, the
/// export-only crop and mirror, the file names and the folder — every value the one applied.
struct ExportForm: View {
  @Bindable var model: ExportStageModel
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      files
      formats
      values
      folder
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

  private var folder: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      Text(.app("Folder")).font(.headline)
      Text(verbatim: model.folder.path).font(.caption).textSelection(.enabled)
        .lineLimit(2).truncationMode(.middle)
      Button(.app("Choose…")) { chooseFolder() }
        .accessible(.stageControl("export", "folder"), label: .app("Choose…"))
    }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.directoryURL = model.folder.deletingLastPathComponent()
    guard panel.runModal() == .OK, let url = panel.url else { return }
    model.folder = url
  }

  private func chosen(_ deliverable: ExportSettings.Deliverable) -> Binding<Bool> {
    Binding(
      get: { model.effectiveDeliverables.contains(deliverable) },
      set: { on in
        model.settings.deliverables = ExportSettings.Deliverable.allCases.filter {
          $0 == deliverable ? on : model.settings.deliverables.contains($0)
        }
      })
  }

  private func chosen(_ format: ExportSettings.Format) -> Binding<Bool> {
    Binding(
      get: { model.settings.formats.contains(format) },
      set: { on in
        model.settings.formats = ExportSettings.Format.allCases.filter {
          $0 == format ? on : model.settings.formats.contains($0)
        }
      })
  }

  private func number(
    _ path: WritableKeyPath<ExportSettings, Double>, default value: Double,
    range: ClosedRange<Double>
  ) -> Binding<ParameterValue> {
    Binding(
      get: { ParameterValue(default: value, range: range, value: model.settings[keyPath: path]) },
      set: { model.settings[keyPath: path] = $0.value })
  }

  static func title(_ deliverable: ExportSettings.Deliverable) -> LocalizedStringResource {
    switch deliverable {
    case .final: .app("Final image")
    case .starless: .app("Starless")
    case .stars75: .app("Stars at 75 %")
    case .stars50: .app("Stars at 50 %")
    case .stars25: .app("Stars at 25 %")
    }
  }

  static func title(_ format: ExportSettings.Format) -> LocalizedStringResource {
    switch format {
    case .png16: .app("PNG 16-bit")
    case .tiff16: .app("TIFF 16-bit")
    case .fits32: .app("FITS 32-bit float")
    }
  }

  static func title(_ orientation: ExportSettings.Orientation) -> LocalizedStringResource {
    switch orientation {
    case .none: .app("None")
    case .hflip: .app("Left ↔ right")
    case .vflip: .app("Top ↔ bottom")
    }
  }
}
