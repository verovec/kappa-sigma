/// Siril's deep-sky lists merged into one catalogue (card 0129, port of the legacy
/// `internal/skycat`): one object per sky object, found by any of its names.
///
/// Messier is merged first so its designation wins (`M1` = `NGC1952` = `Sh2-244` is `M1`); a later
/// list only fills what is missing. `normalize` is the single object-name key of the app.
package struct SkyCatalogue: Sendable {
  /// The objects, in merge order.
  package private(set) var objects: [SkyObject] = []
  /// Every normalised name and alias → its object's index; the first owner keeps a key.
  private var index: [String: Int] = [:]

  /// The catalogue of `objects`, merged in order: an object sharing a key with an earlier one is
  /// folded into it (legacy `Catalog.add`).
  package init(objects: [SkyObject]) {
    for object in objects { add(object) }
  }

  /// The object `name` designates (its name or any alias), case and punctuation ignored.
  package func object(named name: String) -> SkyObject? {
    index[Self.normalize(name)].map { objects[$0] }
  }

  /// The object-name key: upper-cased, `A`–`Z` and `0`–`9` only (legacy `normalize`).
  ///
  /// `M 31`, `m-31` and `M31` match. Every comparison of object names goes through it.
  package static func normalize(_ name: String) -> String {
    String(
      String.UnicodeScalarView(
        name.uppercased().unicodeScalars.filter {
          ("A"..."Z").contains($0) || ("0"..."9").contains($0)
        }))
  }

  /// `objects` with each entry replaced by `transform` of it; names and aliases kept, so the index
  /// still holds.
  func mapping(_ transform: (SkyObject) -> SkyObject) -> Self {
    var mapped = self
    mapped.objects = objects.map(transform)
    return mapped
  }

  private mutating func add(_ object: SkyObject) {
    let known = index
    if let owner = object.keys.lazy.compactMap({ known[$0] }).first {
      objects[owner].absorb(object)
      // The merge may have brought new aliases.
      register(owner)
      return
    }
    objects.append(object)
    register(objects.count - 1)
  }

  /// Points every key of object `position` at it, never taking a key from an earlier owner.
  private mutating func register(_ position: Int) {
    for key in objects[position].keys where index[key] == nil {
      index[key] = position
    }
  }
}
