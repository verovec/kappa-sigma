internal import Observation
package import StackKit

/// The sidebar's Objects (card 0130): Siril's catalogue, searched by any name, and the object the
/// plate solve offers.
///
/// The catalogue is read once, off the main actor; the project's object pre-selects its entry
/// through `SkyCatalogue.normalize`, nothing is guessed when it has none. A missing Siril greys
/// the section with its install card (R2): no other list stands in.
@Observable
package final class ObjectSearchModel {
  /// What the search field holds.
  package var query = ""
  /// The object chosen, or the project's own until the user chooses.
  package private(set) var selected: SkyObject?
  /// The object card is in the detail column.
  package private(set) var cardShown = false
  /// Why there is no catalogue, once its load failed.
  package private(set) var unavailable: SkyCatalogueError?
  private var catalogue: SkyCatalogue?
  /// The user chose an object: the project's no longer replaces it.
  private var chosen = false
  @ObservationIgnored private let loader: @Sendable @concurrent () async throws -> SkyCatalogue

  /// A model over `load` (the installed Siril's catalogue in the app).
  package init(
    load: @escaping @Sendable @concurrent () async throws -> SkyCatalogue = {
      try SkyCatalogue.installed()
    }
  ) {
    loader = load
  }

  /// The catalogue's matches for `query`, best first, at most 20.
  package var results: [SkyObject] {
    catalogue?.search(query, limit: 20) ?? []
  }

  /// What the plate solve offers: the selection.
  package var offered: SkyObject? { selected }

  /// Reads the catalogue the first time, then matches `projectObject` (the stack's `OBJECT`)
  /// unless the user chose another object; a name the catalogue lacks selects nothing.
  package func load(projectObject: String?) async {
    if catalogue == nil, unavailable == nil {
      do {
        catalogue = try await loader()
      } catch let error as SkyCatalogueError {
        unavailable = error
      } catch {
        unavailable = .unreadable(file: "", reason: error.localizedDescription)
      }
    }
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

  /// Siril was installed meanwhile: the next load reads the catalogue again.
  package func retry() {
    unavailable = nil
  }
}
