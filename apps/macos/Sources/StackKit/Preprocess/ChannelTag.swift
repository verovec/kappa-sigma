/// File-name tags of a channel (`sanitize`, `filterTag`): `light_<lane>`, `master_<tag>`.
package enum ChannelTag {
  /// Letters, digits, `-` and `_` kept, spaces made `_`, the rest dropped; `session` when empty.
  package static func sanitize(_ text: String) -> String {
    let kept = text.unicodeScalars.compactMap { scalar -> Character? in
      if scalar == " " { return "_" }
      let allowed = scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar))
      return allowed || scalar == "-" || scalar == "_" ? Character(scalar) : nil
    }
    return kept.isEmpty ? "session" : String(kept)
  }

  /// A filter's tag; `mono` for an unfiltered channel.
  package static func of(_ filter: String) -> String {
    filter.isEmpty ? "mono" : sanitize(filter)
  }
}
