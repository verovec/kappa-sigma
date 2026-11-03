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
  @State private var listing = false
  @State private var listingDropped = false
  @State private var browsing = false

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
      headerBar
      droppedBar
      if let panelError = model.panelError {
        StatusBadge(.error, panelError.message)
      }
      // A scan in flight answers the last error: its badge would read as the new scan's failure.
      if let error = model.error, !model.isScanning {
        StatusBadge(.error, error.message)
      }
      content
      footer
    }
    .padding()
    .frame(minWidth: 820, minHeight: 560)
    // A popover whose anchor went with the old selection must not reopen with the next one.
    .onChange(of: model.request.paths) { listing = false }
    .onChange(of: model.droppedFolders) { listingDropped = false }
    .fileImporter(
      isPresented: $picking, allowedContentTypes: [.folder], allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls): model.choose(folders: urls)
      case .failure(let failure): model.panelFailed(failure)
      }
    }
    .fileDialogDefaultDirectory(ImportPlanning.capturesFolder)
  }

  /// What the body of the sheet shows.
  package enum Content: Equatable {
    /// The scanned plan (a rescan runs over it, its progress in the header).
    case plan(ImportPlan)
    /// The overrides after a failed scan: the one that made it fail must stay reachable.
    case failed
    /// The first scan of a folder, with its progress.
    case scanning
    /// Nothing chosen yet.
    case empty
  }

  /// The body `model` calls for: never « No capture » while a scan runs.
  package static func content(of model: ImportViewModel) -> Content {
    if let plan = model.plan { return .plan(plan) }
    if model.isScanning { return .scanning }
    return model.error != nil ? .failed : .empty
  }

  @ViewBuilder
  private var content: some View {
    switch Self.content(of: model) {
    case .plan(let plan):
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ImportInventoryView(model: model, plan: plan)
          ImportProfileView(model: model)
          ImportOverridesView(model: model)
          ImportCalibrationView(model: model, plan: plan)
          warnings(plan.warnings)
        }
      }
    case .failed:
      ImportOverridesView(model: model)
      Spacer()
    case .scanning:
      ImportScanProgressView(progress: model.progress) { model.cancelScan() }
    case .empty where model.source == .bucket:
      EmptyState(
        .app("No prefix chosen"),
        message: .app(
          "Choose a bucket and a prefix: its frames are read where they are, never downloaded."),
        systemImage: "externaldrive.badge.icloud")
    case .empty:
      EmptyState(
        .app("No capture"),
        message: .app("Choose one or more capture folders; they are read, never written."),
        systemImage: "folder")
    }
  }

  /// What the header names for the chosen `paths`.
  package enum Header: Equatable {
    /// Nothing chosen yet.
    case none
    /// One folder, named in full.
    case folder(String)
    /// Several folders, counted, listed on click.
    case folders([String])
  }

  /// The header of `paths`: the one rule for what the top of the sheet says.
  package static func header(of paths: [String]) -> Header {
    switch paths.count {
    case 0: .none
    case 1: .folder(paths[0])
    default: .folders(paths)
    }
  }

  private var headerBar: some View {
    HStack {
      Group {
        switch Self.header(of: model.request.paths) {
        case .none:
          Text(.app("No folder chosen"))
        case .folder(let folder):
          Text(verbatim: folder)
        case .folders(let folders):
          Button(.app("\(folders.count) folders")) { listing = true }
            .buttonStyle(.link)
            .popover(isPresented: $listing) { ImportFolderList(folders: folders) }
        }
      }
      .font(.title3).lineLimit(1).truncationMode(.middle)
      Spacer()
      // Only a scan reports progress: a calibration-only rematch shows nothing to cancel.
      if model.plan != nil, model.progress != nil {
        ImportScanProgressView(progress: model.progress, compact: true) { model.cancelScan() }
      }
      sourceChoice
      switch model.source {
      case .folder:
        Button(.app("Choose Folders…")) { picking = true }
      case .bucket:
        bucketButton
      }
    }
  }

  /// Where the capture is read from (card 0169).
  ///
  /// Folders of this Mac, or a bucket; shown only when the app offers the remote half.
  @ViewBuilder private var sourceChoice: some View {
    // Offered even with no connection yet: the bucket form is the one place that says where to
    // add one, so hiding it until S3 is set up would hide the only instructions.
    if model.bucket != nil {
      Picker(selection: Binding(get: { model.source }, set: { model.setSource($0) })) {
        Text(.app("Folders")).tag(ImportViewModel.Source.folder)
        Text(.app("S3 Bucket")).tag(ImportViewModel.Source.bucket)
      } label: {
        EmptyView()
      }
      .pickerStyle(.segmented)
      .fixedSize()
      .accessible(.importSource, label: .app("Where the capture is read from"))
    }
  }

  /// « Browse… », the bucket form in a popover: it stays reachable after a scan, so another
  /// prefix can be chosen without losing the sheet.
  @ViewBuilder private var bucketButton: some View {
    if let bucket = model.bucket {
      Button(.app("Browse…")) { browsing = true }
        .popover(isPresented: $browsing) {
          ImportBucketView(model: bucket) { target in
            browsing = false
            model.choose(bucket: target)
          }
        }
    }
  }

  /// The chosen folders another chosen one covers: one short badge, however many there are and
  /// however long their paths, listed with their ancestors on click — a target selected with all
  /// its nights never pushes the plan off the sheet nor widens it.
  @ViewBuilder
  private var droppedBar: some View {
    let dropped = model.droppedFolders
    if !dropped.isEmpty {
      Button {
        listingDropped = true
      } label: {
        HStack(spacing: 4) {
          StatusBadge(.attention, .app("\(dropped.count) folders already included in a chosen one"))
          Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)
      .help(Text(.app("Show the dropped folders")))
      .popover(isPresented: $listingDropped) {
        ImportFolderList(dropped: dropped)
      }
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
