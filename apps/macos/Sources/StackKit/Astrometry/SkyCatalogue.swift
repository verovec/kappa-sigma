/// Siril's deep-sky lists merged into one catalogue (card 0129, port of the legacy
/// `internal/skycat`): one object per sky object, found by any of its names.
///
/// Messier is merged first so its designation wins (`M1` = `NGC1952` = `Sh2-244` is `M1`); a later
/// list only fills what is missing. `normalize` is the single object-name key of the app.
package struct SkyCatalogue: Sendable {
  /// One object's searchable names, normalised once: type-ahead never normalises again.
  struct Tokens: Sendable {
    let name: String
    let commonNames: [String]
    let aliases: [String]

    init(_ object: SkyObject) {
      name = SkyCatalogue.normalize(object.name)
      commonNames = object.commonNames.map(SkyCatalogue.normalize)
      aliases = object.aliases.map(SkyCatalogue.normalize)
    }
  }

  /// The objects, in merge order.
  package private(set) var objects: [SkyObject] = []
  /// The search tokens of `objects`, in the same order.
  private(set) var tokens: [Tokens] = []
  /// Every normalised name and alias → its object's index; the first owner keeps a key.
  private var index: [String: Int] = [:]

  /// The catalogue of `objects`, merged in order: an object sharing a key with an earlier one is
  /// folded into it (legacy `Catalog.add`).
  package init(objects: [SkyObject]) {
    for object in objects { add(object) }
    tokens = self.objects.map(Tokens.init)
  }

  /// The object `name` designates (its name or any alias), case and punctuation ignored.
  package func object(named name: String) -> SkyObject? {
    index[Self.normalize(name)].map { objects[$0] }
  }

  /// The object-name key: ASCII letters upper-cased, `A`–`Z` and `0`–`9` only (legacy `normalize`).
  ///
  /// `M 31`, `m-31` and `M31` match. Every comparison of object names goes through it. Byte by
  /// byte, as the legacy rune-wise upper-casing: `ß` is dropped, never expanded to `SS`.
  package static func normalize(_ name: String) -> String {
    let bytes = name.utf8.compactMap { byte -> UInt8? in
      switch byte {
      case UInt8(ascii: "a")...UInt8(ascii: "z"): byte - 32
      case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"): byte
      default: nil
      }
    }
    return String(String.UnicodeScalarView(bytes.map(Unicode.Scalar.init)))
  }

  /// `objects` with each entry replaced by `transform` of it; names and aliases kept, so the index
  /// still holds (the search tokens are rebuilt: common names may change).
  func mapping(_ transform: (SkyObject) -> SkyObject) -> Self {
    var mapped = self
    mapped.objects = objects.map(transform)
    mapped.tokens = mapped.objects.map(Tokens.init)
    return mapped
  }

  private mutating func add(_ object: SkyObject) {
    var owner: Int?
    for key in object.keys {
      if let found = index[key] {
        owner = found
        break
      }
    }
    if let owner {
      objects[owner].absorb(object)
      // The merge may have brought new aliases.
      register(owner)
    } else {
      objects.append(object)
      register(objects.count - 1)
    }
  }

  /// Points every key of object `position` at it, never taking a key from an earlier owner.
  private mutating func register(_ position: Int) {
    for key in objects[position].keys where index[key] == nil {
      index[key] = position
    }
  }
}
