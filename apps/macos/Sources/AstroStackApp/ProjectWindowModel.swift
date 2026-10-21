internal import Observation
package import ProjectKit
package import StackKit

/// The state of a project window: the journey stage shown and every stage's status, the
/// sources, and the Import sheet when one is open.
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
  package internal(set) var scan: ImportPlan?
  /// A Rescan is running.
  package internal(set) var isScanning = false
  var scanTask: Task<Void, Never>?

  let store: () -> ProjectStore?
  let services: (ProjectStore?) -> ImportServices

  /// A window over the document's current store (it changes when the package moves); each sheet
  /// gets fresh `services`.
  package init(
    store: @escaping () -> ProjectStore?,
    services: @escaping (ProjectStore?) -> ImportServices = { ImportPlanning.services(store: $0) }
  ) {
    self.store = store
    self.services = services
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
    planning: @escaping (ProjectStore?) -> ImportViewModel.Planning
  ) {
    self.init(store: store, services: { ImportServices(planning: planning($0)) })
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

  /// Records the imported folders as read-only sources of the project and closes the sheet.
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
      // The sheet's plan is this import's scan: the Données stage shows it without rescanning.
      if let plan = importing?.plan, importing?.request == request {
        cancelScan()
        scan = plan
      }
      closeImport()
      refresh()
    } catch {
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
      statuses = JourneyState.derive(from: ProjectFacts(summary: summary, coverage: coverage))
      error = nil
    } catch {
      self.error = UserFacingError(error)
    }
  }
}
