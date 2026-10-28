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
  /// Where the next export writes: the folder chosen, else `defaultFolder` (computed when read:
  /// the package may have moved, the day changed).
  package var folder: URL {
    get {
      chosenFolder
        ?? Self.defaultFolder(
          in: packageFolder(), stack: stack, date: defaultStamp, zone: services.timeZone)
    }
    set { chosenFolder = newValue }
  }
  /// The time the default folder is named after: the one shown is the one written to (R2), a
  /// new one after each export.
  private var defaultStamp: Date
  /// The folder the user chose, `nil` for the default.
  private var chosenFolder: URL?
  /// An export is being written.
  package private(set) var isExporting = false
  /// The files the last export wrote, in write order.
  package private(set) var written: [URL] = []
  /// This stack's exports, newest first.
  package private(set) var exports: [ProjectExport] = []
  /// Why the last separation or export failed.
  package private(set) var failure: UserFacingError?
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
  @ObservationIgnored private let store: ProjectStore
  @ObservationIgnored private let services: ExportServices
  @ObservationIgnored private let packageFolder: () -> URL
  @ObservationIgnored private let onSeparated: () -> Void
  @ObservationIgnored private let onExported: () -> Void
  @ObservationIgnored private var separation: Task<Void, Never>?

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
    defaultStamp = services.now()
    refresh()
  }

  /// `<package>/exports/<stack folder name>/<yyyy-MM-dd-HHmmss>/`: deliverables are not state,
  /// so never inside the stack's own folder; one folder per export, so none overwrites another.
  nonisolated static func defaultFolder(
    in package: URL, stack: ProjectStack, date: Date, zone: TimeZone
  ) -> URL {
    let hour = Date.FormatStyle.Symbol.VerbatimHour.twoDigits(
      clock: .twentyFourHour, hourCycle: .zeroBased)
    let day: Date.FormatString = "\(year: .padded(4))-\(month: .twoDigits)-\(day: .twoDigits)"
    let time: Date.FormatString = "\(hour: hour)\(minute: .twoDigits)\(second: .twoDigits)"
    let calendar = Calendar(identifier: .gregorian)
    let name = [day, time].map {
      date.formatted(Date.VerbatimFormatStyle(format: $0, timeZone: zone, calendar: calendar))
    }.joined(separator: "-")
    let stackName = URL(fileURLWithPath: stack.bundlePath).lastPathComponent
    return package.appendingPathComponent("exports", isDirectory: true)
      .appendingPathComponent(stackName, isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
  }

  /// The deliverables that need a starless while there is none: greyed, never written.
  package var unavailableDeliverables: Set<ExportSettings.Deliverable> {
    hasStarless ? [] : Set(ExportSettings.Deliverable.allCases).subtracting([.final])
  }

  /// The deliverables the next export writes: the chosen ones that can be made.
  package var effectiveDeliverables: [ExportSettings.Deliverable] {
    settings.deliverables.filter { !unavailableDeliverables.contains($0) }
  }

  /// Something can be written: one deliverable in one format, nothing else running.
  package var canExport: Bool {
    !effectiveDeliverables.isEmpty && !settings.formats.isEmpty && !isExporting && !isSeparating
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

  // MARK: - Export

  /// Writes the deliverable set of the head into `folder` and records it; a folder under the
  /// read-only sources is refused before anything is written.
  package func export() async {
    guard !isExporting else { return }
    failure = nil
    written = []
    let folder = self.folder
    let astro = services.astro()
    guard ExportGuard.refusal(for: folder, astro: astro) == nil else {
      failure = .exportReadOnlyFolder(path: folder.path)
      return
    }
    var settings = self.settings
    settings.deliverables = effectiveDeliverables
    guard !settings.deliverables.isEmpty, !settings.formats.isEmpty else {
      failure = .exportNothingChosen
      return
    }
    let taken = settings.deliverables.flatMap { deliverable in
      settings.formats.map { folder.appendingPathComponent(settings.fileName(deliverable, $0)) }
    }
    .filter { FileManager.default.fileExists(atPath: $0.path) }
    if let first = taken.first {
      failure = .exportWouldOverwrite(path: first.path)
      return
    }
    isExporting = true
    // Written or not (a failure may leave part of the set), the next default folder is a new
    // one, a second later at least: folder names are to the second.
    defer {
      isExporting = false
      if chosenFolder == nil {
        defaultStamp = max(services.now(), defaultStamp.addingTimeInterval(1))
      }
    }
    do {
      // The head the files are rendered from, before the Studio can move on.
      let head = try store.images(stackID: stack.id).first { $0.id == studio.imageID }?.headStepID
      let urls = try await Self.write(
        original: Self.detached(studio.session.history.current),
        starless: starless(),
        settings: settings, to: folder, astro: astro, device: studio.session.device)
      let json = String(bytes: try JSONEncoder().encode(settings), encoding: .utf8) ?? "{}"
      try store.addExport(
        stackID: stack.id, imageID: studio.imageID, headStepID: head, folder: folder.path,
        settingsJSON: json, files: urls.map(\.lastPathComponent))
      written = urls
      refresh()
      onExported()
    } catch {
      failure = UserFacingError(error)
    }
  }

  /// Shows the files of `export` in the Finder.
  package func reveal(_ export: ProjectExport) {
    let folder = URL(fileURLWithPath: export.folder, isDirectory: true)
    services.reveal(
      export.files.isEmpty ? [folder] : export.files.map(folder.appendingPathComponent))
  }

  /// Where the head's starless is: the latest StarNet step's file, else the bundle's own layer
  /// (a legacy run's), a copy.
  private enum Starless {
    case file(URL)
    case image(AstroImage)
    case none
  }

  private func starless() -> sending Starless {
    if let file = studio.session.history.layerFile(.starless) { return .file(file) }
    guard let layer = studio.session.bundle.layers[LayerRole.starless.rawValue] else {
      return .none
    }
    return .image(Self.detached(layer))
  }

  /// A copy of `image` of its own, which may cross to another task.
  private nonisolated static func detached(_ image: AstroImage) -> sending AstroImage {
    AstroImage(
      width: image.width, height: image.height, planes: image.planes, metadata: image.metadata)
  }

  /// Reading the starless step's FITS, rendering the star tiers and encoding 16-bit files take
  /// seconds at 22 Mpx: off the main actor, on images of its own.
  @concurrent
  private nonisolated static func write(
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

  /// Rereads this stack's exports.
  private func refresh() {
    do {
      exports = try store.exports(stackID: stack.id)
    } catch {
      failure = UserFacingError(error)
    }
  }
}
