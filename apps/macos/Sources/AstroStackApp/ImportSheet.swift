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
  var addError: String?
  @State private var picking = false

  /// A sheet over `model`; `onAdd` receives the request as the user left it.
  package init(
    model: ImportViewModel, onAdd: @escaping (ImportRequest) -> Void,
    onCancel: @escaping () -> Void, addError: String? = nil
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
        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
      }
      if let plan = model.plan {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            ImportInventoryView(model: model, plan: plan)
            ImportOverridesView(model: model)
            ImportCalibrationView(model: model, plan: plan)
            warnings(plan.warnings)
          }
        }
      } else if model.error != nil {
        // The override that made the scan fail must stay reachable to undo it.
        ImportOverridesView(model: model)
        Spacer()
      } else {
        ContentUnavailableView(
          "No capture", systemImage: "folder",
          description: Text("Choose a capture folder; it is read, never written."))
      }
      footer
    }
    .padding()
    .frame(minWidth: 820, minHeight: 560)
    .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result { model.choose(folder: url) }
    }
    .fileDialogDefaultDirectory(ImportPlanning.capturesFolder)
  }

  private var header: some View {
    HStack {
      Text(model.request.paths.first ?? "No folder chosen")
        .font(.title3).lineLimit(1).truncationMode(.middle)
      Spacer()
      if model.isScanning { ProgressView().controlSize(.small) }
      Button("Choose Folder…") { picking = true }
    }
  }

  @ViewBuilder
  private func warnings(_ warnings: [String]) -> some View {
    if !warnings.isEmpty {
      GroupBox("Warnings") {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var footer: some View {
    HStack {
      Text("Library: \(ImportPlanning.libraryFolder.path)")
        .font(.caption).foregroundStyle(.secondary)
      Spacer()
      if let addError {
        Text(addError).foregroundStyle(.red).lineLimit(2)
      }
      Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
      Button("Add to Project") { onAdd(model.request) }
        .keyboardShortcut(.defaultAction)
        .disabled(model.plan == nil || model.isScanning)
    }
  }
}
