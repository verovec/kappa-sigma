internal import FilterKit
package import Metal

/// One plane of a bundle layer, named as panels and the bundle name it: `R` (a mono layer's
/// plane) or `RGB.r`, `RGB.g`, `RGB.b` (a plane of the colour layer).
package struct LayerPlane: Equatable, Sendable {
  /// The layer id (`RGB`, `R`, `Ha`…).
  package let layer: String
  /// The plane in that layer.
  package let plane: Int
  /// The name it was made from.
  package let token: String

  /// The plane suffixes of a 3-plane layer, in plane order (`RGB.r` is plane 0).
  package static let planeNames = ["r", "g", "b"]

  /// The plane `token` names.
  package init(_ token: String) {
    self.token = token
    if let dot = token.lastIndex(of: "."),
      let plane = Self.planeNames.firstIndex(of: String(token[token.index(after: dot)...]))
    {
      layer = String(token[..<dot])
      self.plane = plane
    } else {
      layer = token
      plane = 0
    }
  }

  /// The plane's texture among the bundle `layers`, which must be `width` × `height`.
  ///
  /// A missing layer or plane is an error, never another plane (R2); a layer of another size
  /// would be read at the wrong pixels.
  package func texture(in layers: [String: GPUImage], width: Int, height: Int) throws
    -> MTLTexture
  {
    guard let image = layers[layer] else { throw ProcessError.missingLayer(layer) }
    guard image.width == width, image.height == height else { throw ProcessError.sizeMismatch }
    // A plane token (`L.r`) of a 1-plane layer is refused like `L.g`, never read as plane 0.
    guard plane < image.planes.count, token == layer || image.planes.count >= Self.planeNames.count
    else { throw ProcessError.missingLayer(token) }
    return image.planes[plane]
  }

  /// The plane's bundle statistics, if the bundle has them per plane.
  ///
  /// A colour plane (`RGB.r`) needs one entry per plane: a single entry averaged over the planes
  /// is not the red plane's, so it gives none rather than the average.
  package func stats(in layerStats: [String: LayerStats]) -> ChannelStats? {
    guard let channels = layerStats[layer]?.channels, plane < channels.count,
      token == layer || channels.count >= 3
    else { return nil }
    return channels[plane]
  }

  // MARK: - Tokens a layer parameter takes (card 0138)

  /// Whether `token` is a layer token by grammar — `none` (when allowed), `<id>` or `<id>.r|g|b`
  /// for any id the bundle may carry (a FITS filter name kept verbatim: non-empty, trimmed, no
  /// `*`), or `<a>*<b>` of two different whole layers (when allowed) — the bundle being the only
  /// judge of whether the layer exists.
  package static func isWellFormed(_ token: String, allowsNone: Bool, allowsProduct: Bool)
    -> Bool
  {
    if token == "none" { return allowsNone }
    let parts = token.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
    switch parts.count {
    case 1:
      return isLayerID(Self(parts[0]).layer)
    case 2 where allowsProduct:
      // √(A·B) multiplies two whole layers: no plane, no `none`, two different ids.
      return parts[0] != parts[1]
        && parts.allSatisfy { isLayerID($0) && $0 != "none" && Self($0).layer == $0 }
    default:
      return false
    }
  }

  /// A layer id as the bundle may name one: non-empty, trimmed, without `*`, not `none`.
  private static func isLayerID(_ id: String) -> Bool {
    guard let first = id.first, let last = id.last, id != "none" else { return false }
    return !first.isWhitespace && !last.isWhitespace && !id.contains("*")
  }

  /// The tokens a bundle of `layerIDs` (with `planes` per layer, 1 when unsaid) offers: `none`
  /// first when allowed; the colour layer first, then the canonical filter order; a plane per
  /// 3-plane layer; and, when allowed, the product of every pair of lines present.
  package static func options(
    layerIDs: Set<String>, planes: [String: Int], allowsNone: Bool, allowsProduct: Bool
  ) -> [String] {
    let ids = layerIDs.sorted { lhs, rhs in
      if lhs == Filter.color || rhs == Filter.color { return lhs == Filter.color }
      return Filter.less(lhs, rhs)
    }
    var options = allowsNone ? ["none"] : []
    for id in ids {
      options += planes[id] == planeNames.count ? planeNames.map { "\(id).\($0)" } : [id]
    }
    guard allowsProduct else { return options }
    // √(A·B) multiplies two whole lines: a 3-plane line (offered by plane) makes no product.
    let lines = ids.filter { Filter.isNarrowband($0) && planes[$0] != planeNames.count }
    for (index, first) in lines.enumerated() {
      options += lines[(index + 1)...].map { "\(first)*\($0)" }
    }
    return options
  }
}
