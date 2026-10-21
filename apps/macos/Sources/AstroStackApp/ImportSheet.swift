internal import RenderKit
package import StackKit
package import SwiftUI
internal import UniformTypeIdentifiers

/// The Import sheet: pick a capture folder, see what the scan understood and the calibration it
/// will use, override any verdict, then add the capture to the project.
package struct ImportSheet: View {
  var model: ImportViewModel
  var onAdd: (ImportRequest) -> Void
  var onCancel: () -> Void
  /// Why the last Add failed, shown in the sheet (the window behind it is covered).
  var addError: UserFacingError?
  @State private var picking = false

  /// A sheet over `model`; `onAdd` receives the request as the user left it.
  package init(
    model: ImportViewModel, onAdd: @escaping (ImportRequest) -> Void,
    onCancel: @escaping () -> Void, addError: UserFacingError? = nil
  ) {
    self.model = model
    self.addError = addError
    self.onAdd = onAdd
    self.onCancel = onCancel
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if let error = model.error {
        StatusBadge(.error, error.message)
      }
      content
      footer
    }
    .padding()
    .frame(minWidth: 820, minHeight: 560)
    .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result { model.choose(folder: url) }
    }
    .fileDialogDefaultDirectory(ImportPlanning.capturesFolder)
  }

  /// What the body of the sheet shows.
  package enum Content: Equatable {
    /// The scanned plan (a rescan runs over it, its progress in the header).
    case plan
    /// The overrides after a failed scan: the one that made it fail must stay reachable.
    case failed
    /// The first scan of a folder, with its progress.
    case scanning
    /// Nothing chosen yet.
    case empty
  }

  /// The body `model` calls for: never « No capture » while a scan runs.
  package static func content(of model: ImportViewModel) -> Content {
    if model.plan != nil { return .plan }
    if model.isScanning { return .scanning }
    return model.error != nil ? .failed : .empty
  }

  @ViewBuilder
  private var content: some View {
    switch Self.content(of: model) {
    case .plan:
      if let plan = model.plan {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            ImportInventoryView(model: model, plan: plan)
            ImportOverridesView(model: model)
            ImportCalibrationView(model: model, plan: plan)
            warnings(plan.warnings)
          }
        }
      }
    case .failed:
      ImportOverridesView(model: model)
      Spacer()
    case .scanning:
      ImportScanProgressView(progress: model.progress) { model.cancelScan() }
    case .empty:
      EmptyState(
        .app("No capture"), message: .app("Choose a capture folder; it is read, never written."),
        systemImage: "folder")
    }
  }

  private var header: some View {
    HStack {
      Group {
        if let folder = model.request.paths.first {
          Text(verbatim: folder)
        } else {
          Text(.app("No folder chosen"))
        }
      }
      .font(.title3).lineLimit(1).truncationMode(.middle)
      Spacer()
      if model.isScanning && model.plan != nil {
        ImportScanProgressView(progress: model.progress, compact: true) { model.cancelScan() }
      }
      Button(.app("Choose Folder…")) { picking = true }
    }
  }

  /// The scan's warnings, as StackKit words them.
  @ViewBuilder
  private func warnings(_ warnings: [String]) -> some View {
    if !warnings.isEmpty {
      GroupBox {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(warnings, id: \.self) { StatusBadge(.attention, verbatim: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text(.app("Warnings"))
      }
    }
  }

  private var footer: some View {
    HStack {
      Text(.app("Library: \(ImportPlanning.libraryFolder.path)"))
        .font(.caption).foregroundStyle(.secondary)
      Spacer()
      if let addError {
        StatusBadge(.error, addError.message).lineLimit(2)
      }
      Button(.app("Cancel"), role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
      Button(.app("Add to Project")) { onAdd(model.request) }
        .keyboardShortcut(.defaultAction)
        .disabled(model.plan == nil || model.isScanning)
    }
  }
}
