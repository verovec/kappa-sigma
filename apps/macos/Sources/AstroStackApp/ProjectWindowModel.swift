internal import Observation
package import ProjectKit
package import StackKit

/// The state of a project window: its sources and the Import sheet when one is open.
@Observable
package final class ProjectWindowModel {
  package private(set) var sources: [ProjectSource] = []
  /// The open Import sheet's model, `nil` when no sheet is shown.
  package var importing: ImportViewModel?
  package private(set) var error: String?

  private let store: () -> ProjectStore?
  private let services: (ProjectStore?) -> ImportServices

  /// A window over the document's current store (it changes when the package moves); each sheet
  /// gets fresh `services`.
  package init(
    store: @escaping () -> ProjectStore?,
    services: @escaping (ProjectStore?) -> ImportServices = { ImportPlanning.services(store: $0) }
  ) {
    self.store = store
    self.services = services
    refresh()
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
    let services = services(store())
    importing = ImportViewModel(planning: services.planning, masters: services.masters)
  }

  /// Records the imported folders as read-only sources of the project and closes the sheet.
  ///
  /// Recording is idempotent per folder: after a failure part-way, Add again records the rest.
  package func add(_ request: ImportRequest) {
    guard let store = store() else {
      error = "this project is not open any more; reopen it and import again"
      return
    }
    do {
      for path in request.paths {
        try store.addSource(kind: .night, path: path)
      }
      importing = nil
      refresh()
    } catch {
      refresh()
      self.error = "\(error)"
    }
  }

  /// Rereads the sources.
  package func refresh() {
    do {
      sources = try store()?.sources() ?? []
      error = nil
    } catch {
      self.error = "\(error)"
    }
  }
}
