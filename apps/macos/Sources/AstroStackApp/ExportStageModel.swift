package import Foundation
internal import ImageKit
internal import Metal
internal import Observation
package import ProcessKit
package import ProjectKit
package import RenderKit
internal import StackKit

/// The Export stage of one stack (card 0091): StarNet run on the Studio's head as a history
/// step, the deliverable set written from the head and its starless, each export recorded.
///
/// Nothing runs on its own: separation and export happen on the user's click, with the values
/// shown (R2); a missing StarNet shows its install card and nothing else is offered.
@Observable
package final class ExportStageModel {
  /// StarNet's progress (0…1) during the separation running or last run, in order.
  package private(set) var progress: [Double] = []
  /// A separation is running.
  package private(set) var isSeparating = false
  /// StarNet's install card after it was found missing or unusable (`nil`: no verdict yet).
  package private(set) var installCard: InstallCardModel?
  /// Why StarNet cannot be used, under its install card.
  package private(set) var installReason: LocalizedStringResource?
  /// What the next export writes: the form's values.
  package var settings = ExportSettings()
  /// The base folder of the next export: Settings' when the stage opened, « Choose… » changes it
  /// for this export — read once, so the folder shown is the folder written (R2).
  package var base: URL
  /// The sub-path template of the next export, Settings' when the stage opened; edited here for
  /// this export.
  package var template: String
  /// « Remember as default »: the export makes its base, template and targets Settings' own.
  package var remember = false
  /// The next export writes its files on this Mac (card 0152).
  package var local: Bool
  /// The next export's S3 copy, `nil` for none (card 0152).
  package var s3: S3Target? {
    // What the last export's key could not check says nothing of another target (card 0185).
    didSet { if s3 != oldValue { remoteUnchecked = false } }
  }
  /// The S3 connections the form offers, as Settings held them when last read (card 0177).
  package internal(set) var s3Connections: [S3Connection]
  /// The file being uploaded, n of N, while an S3 copy runs.
  package internal(set) var uploadProgress: (file: Int, files: Int)?
  /// The last export's S3 key could not look for objects already there (a write-only key: HEAD
  /// answers 403): the service alone refused an overwrite then, where it can (card 0185).
  package internal(set) var remoteUnchecked = false
  /// The time `{date}` and `{time}` stand for: the one shown is the one written to (R2), a new
  /// one after each export.
  var stamp: Date
  /// An export is being written (or its S3 copy uploaded).
  package internal(set) var isExporting = false
  /// The files the last export wrote on this Mac, in write order.
  package internal(set) var written: [URL] = []
  /// This stack's exports, newest first.
  package private(set) var exports: [ProjectExport] = []
  /// Why the last separation or export failed.
  package internal(set) var failure: UserFacingError?
  /// The head has a starless layer (a StarNet step, or the bundle's own); follows every move of
  /// the Studio's history (its `steps` are observed).
  package var hasStarless: Bool {
    studio.steps.contains { $0.outputs[.starless] != nil }
      || studio.session.bundle.layers[LayerRole.starless.rawValue] != nil
  }
  /// Steps applied after the last StarNet step: what the starless does not contain.
  ///
  /// Shown, the user decides whether to separate again. A geometry step moves the starless with
  /// the image (card 0090): it neither makes a new starless nor counts as missing from it.
  package var stepsAfterStarless: Int {
    let moving = studio.session.registry.movingIDs
    let steps = studio.steps
    guard
      let last = steps.lastIndex(where: {
        $0.outputs[.starless] != nil && !moving.contains($0.processID)
      })
    else { return 0 }
    return steps[(last + 1)...].filter { !moving.contains($0.processID) }.count
  }

  /// The Studio whose head is exported.
  @ObservationIgnored package let studio: StudioModel
  /// The stack exported.
  @ObservationIgnored package let stack: ProjectStack
  @ObservationIgnored let store: ProjectStore
  @ObservationIgnored let services: ExportServices
  @ObservationIgnored let packageFolder: () -> URL
  @ObservationIgnored private let onSeparated: () -> Void
  @ObservationIgnored let onExported: () -> Void
  @ObservationIgnored private var separation: Task<Void, Never>?
  @ObservationIgnored var exportTask: Task<Void, Never>?

  /// The Export stage of `stack` over `studio`, in the project package at `packageFolder` (read
  /// at each use: a saved untitled project moves); `onSeparated` runs after a recorded StarNet
  /// step (the Studio shows it), `onExported` after a recorded export (the stage states follow).
  package init(
    studio: StudioModel, stack: ProjectStack, store: ProjectStore,
    packageFolder: @escaping () -> URL, services: ExportServices,
    onSeparated: @escaping () -> Void = {}, onExported: @escaping () -> Void = {}
  ) {
    self.studio = studio
    self.stack = stack
    self.store = store
    self.services = services
    self.packageFolder = packageFolder
    self.onSeparated = onSeparated
    self.onExported = onExported
    base = services.destination.base
    template = services.destination.template.text
    local = services.destination.local
    s3 = services.destination.s3
    s3Connections = services.s3Connections()
    stamp = services.now()
    refresh()
  }

  /// The deliverables that need a starless while there is none: greyed, never written.
  package var unavailableDeliverables: Set<ExportSettings.Deliverable> {
    hasStarless ? [] : Set(ExportSettings.Deliverable.allCases).subtracting([.final])
  }

  /// The deliverables the next export writes: the chosen ones that can be made.
  package var effectiveDeliverables: [ExportSettings.Deliverable] {
    settings.deliverables.filter { !unavailableDeliverables.contains($0) }
  }

  /// Something can be written: one deliverable in one format into a folder the template names,
  /// nothing else running.
  package var canExport: Bool {
    !effectiveDeliverables.isEmpty && !settings.formats.isEmpty && !isExporting && !isSeparating
      && folder != nil && (local || s3 != nil)
  }

  // MARK: - Star separation

  /// « Separate stars »: starts the separation unless one runs.
  package func startSeparation() {
    guard separation == nil else { return }
    separation = Task { [weak self] in
      await self?.separateStars()
      self?.separation = nil
    }
  }

  /// Stops the running separation: StarNet is terminated, no step is recorded.
  package func cancelSeparation() {
    separation?.cancel()
  }

  /// Runs StarNet on the head and records the step `starnet` with its starless layer; a
  /// StarNet this Mac lacks or cannot run shows its install card instead (no fallback, R2).
  package func separateStars() async {
    guard !isSeparating else { return }
    failure = nil
    let runner: StarNetRunner
    do {
      runner = try await StarNetRunner.located(by: services.tools)
    } catch {
      showInstallCard(for: error)
      return
    }
    installCard = nil
    installReason = nil
    isSeparating = true
    progress = []
    defer { isSeparating = false }
    let (stream, sink) = AsyncStream.makeStream(of: Double.self)
    // The percentages come from StarNet's task: one consumer keeps them in order.
    let consumer = Task { [weak self] in
      for await fraction in stream { self?.progress.append(fraction) }
    }
    do {
      try await studio.apply(
        StarSeparation.process(runner, scratch: services.scratch), id: StarSeparation.id,
        params: ParamSet(schema: StarSeparation.schema)
      ) { sink.yield($0) }
      onSeparated()
    } catch StarNetError.probeTimedOut(let path) where !Task.isCancelled {
      // Its command line is probed when it runs: an unusable StarNet like a missing one (a
      // cancel during the probe reads as a time-out: nothing to report then).
      showInstallCard(for: StarNetError.probeTimedOut(path: path))
    } catch {
      // Cancelled by the user: StarNet was stopped (it exits on SIGTERM, which reads as a
      // failure), nothing is recorded, nothing to report.
      if !Task.isCancelled { failure = UserFacingError(error) }
    }
    sink.finish()
    await consumer.value
    refresh()
  }

  private func showInstallCard(for error: any Error) {
    let state: InstallCardModel.State
    switch error {
    case StarNetError.missing:
      state = .missing
    case StarNetError.cannotRun(let path, let reason):
      state = WelcomeModel.cardState(.cannotRun(path: path, reason: reason))
    case StarNetError.probeTimedOut(let path):
      let reason = String(localized: UserFacingError(error).message)
      state = .unusable(path: URL(fileURLWithPath: path), reason: reason)
    default:
      failure = UserFacingError(error)
      return
    }
    // The card's badge and its own line say why it cannot run (card 0108).
    installReason = .app("Separates the stars from the nebula.")
    installCard = InstallCardModel(state: state, check: StarSeparation.check(services.tools))
  }

  /// Rereads this stack's exports.
  func refresh() {
    do {
      exports = try store.exports(stackID: stack.id)
    } catch {
      failure = UserFacingError(error)
    }
  }
}
