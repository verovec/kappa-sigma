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

  /// The plane `token` names.
  package init(_ token: String) {
    self.token = token
    let planes = ["r": 0, "g": 1, "b": 2]
    if let dot = token.lastIndex(of: "."),
      let plane = planes[String(token[token.index(after: dot)...])]
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
    guard plane < image.planes.count else { throw ProcessError.missingLayer(token) }
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

  /// Whether `token` is a layer token by grammar — `none` (when allowed), `<id>`, `<id>.r|g|b`,
  /// or `<a>*<b>` of two such (when allowed), ids non-empty without spaces, dots or stars — the
  /// bundle being the only judge of whether the layer exists.
  package static func isWellFormed(_ token: String, allowsNone: Bool, allowsProduct: Bool)
    -> Bool
  {
    if token == "none" { return allowsNone }
    let parts = token.split(separator: "*", omittingEmptySubsequences: false)
    guard parts.count == 1 || (parts.count == 2 && allowsProduct) else { return false }
    return parts.allSatisfy { part in
      let layer = Self(String(part)).layer
      return !layer.isEmpty && layer.allSatisfy { !$0.isWhitespace && $0 != "." && $0 != "*" }
    }
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
      options += planes[id] == 3 ? ["r", "g", "b"].map { "\(id).\($0)" } : [id]
    }
    guard allowsProduct else { return options }
    let lines = ids.filter(Filter.isNarrowband)
    for (index, first) in lines.enumerated() {
      options += lines[(index + 1)...].map { "\(first)*\($0)" }
    }
    return options
  }
}
