package import Foundation
internal import Observation
package import ProjectKit
package import StackKit

/// The state of a project window: the journey stage shown and every stage's status, the
/// sources, the Import sheet when one is open, the preprocessing run and the stack in the Studio.
@Observable
package final class ProjectWindowModel {
  /// The stage the user chose, restored per project; only `select` changes it.
  package private(set) var selection = JourneyStage.data
  /// Every stage's status, derived from the project on each refresh.
  package private(set) var statuses = JourneyState.derive(from: ProjectFacts())
  package private(set) var sources: [ProjectSource] = []
  /// The open Import sheet's model, `nil` when no sheet is shown.
  package private(set) var importing: ImportViewModel?
  package internal(set) var error: UserFacingError?
  /// The last scan of the sources in this window: the sheet's plan on Add, or a Rescan the user
  /// asked for; `nil` until then (an M31 scan takes ~90 s, never run on open).
  package internal(set) var scan: ImportPlan? {
    didSet {
      integration = scan.map { IntegrationSummary.make(inventory: $0.inventory) }
      coverage = scan.map(CoverageMatrix.init(plan:))
    }
  }
  /// The lights per filter × night of `scan`, computed once per scan.
  package private(set) var integration: IntegrationSummary?
  /// The calibration coverage of `scan`, the matcher's verdict as is.
  package private(set) var coverage: CoverageMatrix?
  /// A Rescan is running.
  package internal(set) var isScanning = false
  /// The request `scan` was planned for, the user's import choices included: a Rescan of the
  /// same sources keeps them (the request itself is not persisted before 0057).
  var scanRequest: ImportRequest?
  var scanTask: Task<Void, Never>?
  /// The preprocessing run the Stacking stage shows: the one running, or the last one.
  package internal(set) var run: RunViewModel?
  /// The stack the Studio shows: the latest one, read-only.
  package internal(set) var studio: LegacyRunModel?
  /// This session's imports, in order: the next run applies all their overrides.
  var imports: [ImportRequest] = []

  let store: () -> ProjectStore?
  let folder: () -> URL?
  let services: (ProjectStore?) -> ImportServices
  let runs: RunServices
  /// The package is saved (not the untitled temporary one a Save moves).
  let isSaved: () -> Bool

  /// A window over the document's current store and package folder (both change when the package
  /// moves); each sheet and run gets fresh `services`, and runs go through `runs`.
  package init(
    store: @escaping () -> ProjectStore?,
    folder: @escaping () -> URL? = { nil },
    services: @escaping (ProjectStore?) -> ImportServices = { ImportPlanning.services(store: $0) },
    runs: RunServices = .live,
    isSaved: @escaping () -> Bool = { true }
  ) {
    self.store = store
    self.folder = folder
    self.services = services
    self.runs = runs
    self.isSaved = isSaved
    refresh()
    do {
      let saved = try store()?.setting(JourneyStage.settingKey)
      selection = saved.flatMap(JourneyStage.init(rawValue:)) ?? .data
    } catch {
      self.error = UserFacingError(error)
    }
  }

  /// Shows `stage` and remembers it for this project.
  package func select(_ stage: JourneyStage) {
    guard stage != selection else { return }
    selection = stage
    do {
      try store()?.setSetting(JourneyStage.settingKey, to: stage.rawValue)
    } catch {
      self.error = UserFacingError(error)
    }
  }

  /// A window whose sheets plan with `planning` and have no master services.
  package convenience init(
    store: @escaping () -> ProjectStore?,
    folder: @escaping () -> URL? = { nil },
    planning: @escaping (ProjectStore?) -> ImportViewModel.Planning
  ) {
    self.init(store: store, folder: folder, services: { ImportServices(planning: planning($0)) })
  }

  /// Opens the Import sheet on a fresh request.
  package func startImport() {
    closeImport()
    let services = services(store())
    importing = ImportViewModel(planning: services.planning, masters: services.masters)
  }

  /// Closes the Import sheet and stops its scan, which would otherwise run on for minutes.
  package func closeImport() {
    importing?.cancel()
    importing = nil
  }

  /// Records the imported folders as read-only sources of the project and closes the sheet; the
  /// next run applies the request's overrides.
  ///
  /// Recording is idempotent per folder: after a failure part-way, Add again records the rest.
  package func add(_ request: ImportRequest) {
    guard let store = store() else {
      error = .projectClosed
      return
    }
    do {
      for path in request.paths {
        try store.addSource(kind: .night, path: path)
      }
      imports.append(request)
      let nights = try store.sources().filter { $0.kind == .night }.map(\.path)
      adoptScan(of: importing, for: request, sources: nights)
      closeImport()
      refresh()
    } catch {
      // Some folders may be recorded: the last scan no longer describes the project.
      dropScan()
      refresh()
      self.error = UserFacingError(error)
    }
  }

  /// Rereads the sources and the stage states; never changes the selection.
  package func refresh() {
    do {
      let store = store()
      sources = try store?.sources() ?? []
      let summary = try store?.summary() ?? ProjectSummary()
      let running = run?.isRunning == true ? 1 : 0
      statuses = JourneyState.derive(
        from: ProjectFacts(
          summary: summary, calibrationGaps: coverage?.gaps ?? nil, stacksRunning: running))
      error = nil
    } catch {
      self.error = UserFacingError(error)
    }
  }
}
