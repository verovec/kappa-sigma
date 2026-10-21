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
}
