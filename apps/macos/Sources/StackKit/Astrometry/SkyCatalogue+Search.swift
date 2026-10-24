internal import Foundation

/// Type-ahead over the whole catalogue (legacy `search.go`).
extension SkyCatalogue {
  /// The objects matching `query` by name, common name or alias, best first, at most `limit`.
  ///
  /// Exact before prefix before contains, then the field (name, common name, alias), then Messier →
  /// NGC → IC → Sh2 → LDN, then a known magnitude before none, the brighter first, then merge order.
  /// A blank query or a limit ≤ 0 finds nothing.
  package func search(_ query: String, limit: Int) -> [SkyObject] {
    let key = Self.normalize(query)
    guard !key.isEmpty, limit > 0 else { return [] }
    let hits = tokens.indices.compactMap { position in
      Self.rank(tokens[position], key).map { (position: position, rank: $0) }
    }
    let sorted = hits.sorted { lhs, rhs in
      if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
      let (left, right) = (objects[lhs.position], objects[rhs.position])
      if left.source != right.source { return Self.order(left.source) < Self.order(right.source) }
      switch Self.magnitudeOrder(left, right) {
      case .orderedAscending: return true
      case .orderedDescending: return false
      case .orderedSame: return lhs.position < rhs.position
      }
    }
    return sorted.prefix(limit).map { objects[$0.position] }
  }

  /// The match: how (exact, prefix, contains) then which field; lowest wins, nil for none.
  ///
  /// Exactness dominates, then the primary name over a common name over an alias — but a
  /// contained common name outranks a contained name (the legacy buckets).
  private static func rank(_ tokens: Tokens, _ key: String) -> Int? {
    var best = bucket(tokens.name, key, exact: 0, prefix: 3, contains: 7)
    for token in tokens.commonNames {
      best = min(best, bucket(token, key, exact: 1, prefix: 4, contains: 6))
    }
    for token in tokens.aliases {
      best = min(best, bucket(token, key, exact: 2, prefix: 5, contains: 8))
    }
    return best == Int.max ? nil : best
  }

  /// One normalised token against the key, in its field's buckets; `Int.max` for no match.
  private static func bucket(_ token: String, _ key: String, exact: Int, prefix: Int, contains: Int)
    -> Int
  {
    if token.isEmpty { return Int.max }
    if token == key { return exact }
    if token.hasPrefix(key) { return prefix }
    return token.contains(key) ? contains : Int.max
  }

  /// The list's rank: Messier objects are the famous ones, then NGC/IC, then the surveys.
  private static func order(_ source: SkyObject.Source) -> Int {
    SkyObject.Source.allCases.firstIndex(of: source) ?? 0
  }

  /// `lhs` against `rhs` on magnitude: a known one before none, the brighter first.
  private static func magnitudeOrder(_ lhs: SkyObject, _ rhs: SkyObject) -> ComparisonResult {
    switch (lhs.magnitude, rhs.magnitude) {
    case (let left?, let right?):
      left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
    case (.some, nil): .orderedAscending
    case (nil, .some): .orderedDescending
    case (nil, nil): .orderedSame
    }
  }
}
