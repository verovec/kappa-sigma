package import Foundation
internal import ImageKit
internal import Metal
package import ProcessKit
package import ProjectKit
internal import RenderKit

// MARK: - Export (cards 0091, 0151, 0152)

extension ExportStageModel {
  /// What one export does once every check passed: where, which files, and its S3 copy.
  struct Plan {
    /// The folder the template names under the base (written into when `local`).
    let folder: URL
    /// The files are kept on this Mac.
    let local: Bool
    /// The settings, deliverables narrowed to the ones that can be made.
    let settings: ExportSettings
    /// The S3 copy, checked: client, target, the folder's key.
    let remote: RemotePlan?
  }

  /// « Export »: runs `export()` as a task « Cancel » can stop (an upload in flight).
  @discardableResult
  package func startExport() -> Task<Void, Never>? {
    guard exportTask == nil else { return nil }
    let task = Task { [weak self] in
      await self?.export()
      self?.exportTask = nil
    }
    exportTask = task
    return task
  }

  /// Stops the running export: the S3 copy in flight is aborted (the local files stay).
  package func cancelExport() {
    exportTask?.cancel()
  }

  /// Writes the deliverable set of the head on this Mac and/or uploads it to S3, and records it.
  ///
  /// Every refusal comes before anything is written: no destination, the template, the
  /// read-only sources (R7, on S3 too), a missing chosen base, a file or object already there.
  /// S3-only files are staged in the scratch folder, then removed. An upload that fails after
  /// the local files were written is recorded as failed with the service's words (R2).
  package func export() async {
    guard !isExporting else { return }
    failure = nil
    written = []
    // Busy from the first check: the S3 checks are network calls (no second export, no Resend).
    isExporting = true
    defer {
      isExporting = false
      uploadProgress = nil
    }
    let astro = services.astro()
    guard let plan = await plan(astro: astro) else { return }
    // Written or not (a failure may leave part of the set), the next export's time is a new
    // one, a second later at least: `{time}` is to the second.
    defer { stamp = max(services.now(), stamp.addingTimeInterval(1)) }
    let target =
      plan.local
      ? plan.folder
      : services.scratch.appendingPathComponent("export_\(UUID().uuidString)", isDirectory: true)
    defer { if !plan.local { try? FileManager.default.removeItem(at: target) } }
    do {
      // The head the files are rendered from, before the Studio can move on.
      let head = try store.images(stackID: stack.id).first { $0.id == studio.imageID }?.headStepID
      let urls = try await Self.write(
        original: Self.detached(studio.session.history.current), starless: starless(),
        settings: plan.settings, to: target, astro: astro, device: studio.session.device)
      // S3 only: a failed or cancelled copy leaves nothing behind, in the bucket either.
      let outcome = await upload(urls, to: plan.remote, discardPartial: !plan.local)
      try record(plan, head: head, urls: urls, outcome: outcome)
    } catch {
      failure = UserFacingError(error)
    }
  }

  /// The checks, in order; `nil` with `failure` set when one refuses.
  private func plan(astro: URL) async -> Plan? {
    guard local || s3 != nil else {
      failure = .exportS3(.noDestination)
      return nil
    }
    let folder: URL
    if local {
      switch destinationCheck(astro: astro) {
      case .success(let checked): folder = checked
      case .failure(let refused):
        failure = refused
        return nil
      }
    } else {
      do { folder = try ExportPathTemplate(template).folder(under: base, templateValues) } catch {
        failure = .exportTemplate(error)
        return nil
      }
    }
    var settings = self.settings
    settings.deliverables = effectiveDeliverables
    guard !settings.deliverables.isEmpty, !settings.formats.isEmpty else {
      failure = .exportNothingChosen
      return nil
    }
    let names = settings.deliverables.flatMap { deliverable in
      settings.formats.map { settings.fileName(deliverable, $0) }
    }
    if local, let taken = names.map(folder.appendingPathComponent).first(where: Self.exists) {
      failure = .exportWouldOverwrite(path: taken.path)
      return nil
    }
    var remote: RemotePlan?
    if let s3 {
      guard let checked = await remotePlan(s3, names: names) else { return nil }
      remote = checked
    }
    return Plan(folder: folder, local: local, settings: settings, remote: remote)
  }

  private static func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  /// Records the export; an S3-only one whose upload failed or was cancelled records nothing
  /// (no file remains).
  private func record(_ plan: Plan, head: Int64?, urls: [URL], outcome: UploadOutcome) throws {
    switch outcome {
    case .failed(let text) where !plan.local:
      failure = .exportS3(.service(text))
      return
    case .cancelled where !plan.local:
      return
    default: break
    }
    let json = String(bytes: try JSONEncoder().encode(plan.settings), encoding: .utf8) ?? "{}"
    let status: ProjectExport.RemoteStatus
    let error: String?
    switch outcome {
    case .none: (status, error) = (.none, nil)
    case .done: (status, error) = (.done, nil)
    case .failed(let text): (status, error) = (.failed, text)
    case .cancelled: (status, error) = (.failed, String(localized: .app("Upload cancelled.")))
    }
    try store.addExport(
      stackID: stack.id, imageID: studio.imageID, headStepID: head,
      folder: plan.local ? plan.folder.path : nil, settingsJSON: json,
      files: urls.map(\.lastPathComponent), remoteURL: plan.remote?.url, remoteStatus: status,
      remoteError: error, remoteConnection: plan.remote?.target.connectionID.uuidString)
    written = plan.local ? urls : []
    // Remembered whatever the copy did: the export happened, with these choices.
    let remembered = rememberDestination()
    failure = error.map { .exportS3(.uploadFailed($0)) } ?? remembered
    refresh()
    onExported()
  }

  /// Shows the files of `export` in the Finder.
  package func reveal(_ export: ProjectExport) {
    guard let path = export.folder else { return }
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    services.reveal(
      export.files.isEmpty ? [folder] : export.files.map(folder.appendingPathComponent))
  }

  /// Where the head's starless is: the latest StarNet step's file, else the bundle's own layer
  /// (a legacy run's), a copy.
  enum Starless {
    case file(URL)
    case image(AstroImage)
    case none
  }

  func starless() -> sending Starless {
    if let file = studio.session.history.layerFile(.starless) { return .file(file) }
    guard let layer = studio.session.bundle.layers[LayerRole.starless.rawValue] else {
      return .none
    }
    return .image(Self.detached(layer))
  }

  /// A copy of `image` of its own, which may cross to another task.
  nonisolated static func detached(_ image: AstroImage) -> sending AstroImage {
    AstroImage(
      width: image.width, height: image.height, planes: image.planes, metadata: image.metadata)
  }

  /// Reading the starless step's FITS, rendering the star tiers and encoding 16-bit files take
  /// seconds at 22 Mpx: off the main actor, on images of its own.
  @concurrent
  nonisolated static func write(
    original: sending AstroImage, starless: sending Starless, settings: ExportSettings,
    to folder: URL, astro: URL, device: any MTLDevice
  ) async throws -> [URL] {
    let image: AstroImage? =
      switch starless {
      case .file(let url): try FITSFile.read(at: url).image()
      case .image(let image): image
      case .none: nil
      }
    return try DeliverableExport(device: device).write(
      original: original, starless: image, settings: settings, to: folder, astro: astro)
  }
}
