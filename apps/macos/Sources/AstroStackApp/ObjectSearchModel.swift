internal import Foundation
internal import Observation
package import RenderKit
package import StackKit

/// The sidebar's Objects (card 0130): Siril's catalogue, searched by any name, and the object the
/// plate solve offers.
///
/// The catalogue is read once, off the main actor; the project's object pre-selects its entry
/// through `SkyCatalogue.normalize`, nothing is guessed when it has none. A missing Siril greys
/// the section with its install card (R2): no other list stands in.
@Observable
package final class ObjectSearchModel {
  /// What the search field holds; the results follow.
  package var query = "" {
    didSet { search() }
  }
  /// The catalogue's matches for `query`, best first, at most 20 (one ranking per change).
  package private(set) var results: [SkyObject] = []
  /// The object chosen, or the project's own until the user chooses.
  package private(set) var selected: SkyObject? {
    didSet { if selected != oldValue { onOffer() } }
  }
  /// The object card is in the detail column.
  package private(set) var cardShown = false
  /// Why there is no catalogue, once its load failed.
  package private(set) var unavailable: SkyCatalogueError?
  /// Siril's install card while it is missing; its re-check asks the host-tool client.
  package private(set) var sirilCard: InstallCardModel?
  /// Bumped when Siril is found again: the sidebar's load task restarts on it.
  package private(set) var reloads = 0
  /// Told when the offered object changes: an open plate-solve panel rebuilds its offers.
  @ObservationIgnored package var onOffer: () -> Void = {}
  private var catalogue: SkyCatalogue?
  /// The user chose an object for this project object: it is not replaced until the project's
  /// object changes (another stack).
  private var chosen = false
  /// The project object the last load matched.
  private var lastProjectObject: String?
  /// The read under way: overlapping loads share it.
  @ObservationIgnored private var reading: Task<SkyCatalogue, any Error>?
  @ObservationIgnored private let loader: @Sendable @concurrent () async throws -> SkyCatalogue
  @ObservationIgnored private let locate: @Sendable (HostTool) async -> ToolStatus

  /// A model over `load` (the installed Siril's catalogue in the app) whose install card asks
  /// `locate` (the app's host-tool client).
  package init(
    load: @escaping @Sendable @concurrent () async throws -> SkyCatalogue = {
      try SkyCatalogue.installed()
    },
    locate: @escaping @Sendable (HostTool) async -> ToolStatus = WelcomeWindow.hostTools.locate
  ) {
    loader = load
    self.locate = locate
  }

  /// What the plate solve offers: the selection.
  package var offered: SkyObject? { selected }

  /// The catalogue is being read: a search has nothing to say yet.
  package var isLoading: Bool { catalogue == nil && unavailable == nil }

  /// Reads the catalogue the first time, then matches `projectObject` (the stack's `OBJECT`).
  ///
  /// The user's choice is never replaced; a name the catalogue lacks selects nothing. A load
  /// cancelled meanwhile (the project's object changed) writes nothing.
  package func load(projectObject: String?) async {
    if catalogue == nil, unavailable == nil {
      let reading = self.reading ?? Task { @concurrent [loader] in try await loader() }
      self.reading = reading
      do {
        catalogue = try await reading.value
        search()
      } catch {
        unavailable = Self.failure(error)
        if case .sirilMissing = unavailable { makeSirilCard() }
      }
      self.reading = nil
    }
    guard !Task.isCancelled else { return }
    // Another stack's object: the choice made for the previous one gives way.
    let key = projectObject.map(SkyCatalogue.normalize)
    if key != lastProjectObject.map(SkyCatalogue.normalize) { chosen = false }
    lastProjectObject = projectObject
    guard !chosen else { return }
    selected = projectObject.flatMap { catalogue?.object(named: $0) }
  }

  /// The user picks `object`: its card shows and the plate solve offers it.
  package func choose(_ object: SkyObject) {
    selected = object
    chosen = true
    cardShown = true
  }

  /// Back to the stage: the choice stays offered.
  package func closeCard() {
    cardShown = false
  }

  /// Siril was found by the install card's re-check: the next load reads the catalogue again.
  package func retry() {
    unavailable = nil
    sirilCard = nil
    reloads += 1
  }

  private func search() {
    results = catalogue?.search(query, limit: 20) ?? []
  }

  private func makeSirilCard() {
    let locate = locate
    sirilCard = InstallCardModel(state: .missing) { @concurrent in
      WelcomeModel.cardState(await locate(.siril))
    }
  }

  /// A load's failure as the section words it; another error names the catalogue's folder.
  private static func failure(_ error: any Error) -> SkyCatalogueError {
    if let error = error as? SkyCatalogueError { return error }
    // As `SkyCatalogue.installed` reads it: a symlinked `SIRIL_BIN` names the app's lists.
    let siril = URL(fileURLWithPath: SirilTool.path()).resolvingSymlinksInPath().path
    let folder = SkyCatalogue.folder(sirilPath: siril).path
    return .unreadable(file: folder, reason: error.localizedDescription)
  }
}
