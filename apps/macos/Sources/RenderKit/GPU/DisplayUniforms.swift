/// Swift mirror of `DisplayUniforms` in `Shaders/ShaderTypes.h` — the header is the definition;
/// `ShaderLayoutProbe` pins this layout to what the GPU compiles.
package struct DisplayUniforms {
  /// STF c0 per channel.
  package var shadows: SIMD4<Float>
  /// STF m per channel.
  package var midtone: SIMD4<Float>
  /// STF c1 per channel.
  package var highlights: SIMD4<Float>
  /// 1 or 3.
  package var channels: UInt32
  /// 0: display is clamp(x).
  package var stfEnabled: UInt32
  /// 1: ≥ 1 tinted red, ≤ 0 tinted blue.
  package var clippingOverlay: UInt32
  /// 0 current, 1 reference everywhere, 2 reference left of `splitX`.
  package var compareMode: UInt32
  /// View column of the compare split.
  package var splitX: Float
  /// Image pixels per view pixel.
  package var scale: Float
  /// Image x of the view's top-left pixel.
  package var originX: Float
  /// Image y of the view's top-left pixel.
  package var originY: Float
  /// Image width in pixels.
  package var imageWidth: Float
  /// Image height in pixels.
  package var imageHeight: Float
  /// Mip levels of the image textures.
  package var mipLevels: Float
  /// 1: stored row 0 is the bottom of the frame (`ROWORDER = BOTTOM-UP`), shown last.
  package var flipRows: UInt32 = 0
  /// 1: the mask bound at texture 7 tints the view red by half its value.
  package var maskOverlay: UInt32 = 0
  /// Grey level of view pixels outside the image (`DesignColor.canvasGrey`).
  package var canvasGrey: Float = 0

  /// 1:1 at the image origin, with `stf` per channel (`nil`: STF off).
  package init(image: ImageTexture, stf: [STFParameters]?) {
    self.init(
      width: image.width, height: image.height, mipLevels: image.mipLevels,
      channels: image.planes.count, stf: stf)
  }

  /// 1:1 at the origin of a `width`×`height` image with `channels` planes.
  package init(width: Int, height: Int, mipLevels: Int, channels: Int, stf: [STFParameters]?) {
    let lanes = STFLanes(stf)
    shadows = lanes.shadows
    midtone = lanes.midtone
    highlights = lanes.highlights
    self.channels = UInt32(channels)
    stfEnabled = lanes.enabled
    clippingOverlay = 0
    compareMode = 0
    splitX = 0
    scale = 1
    originX = 0
    originY = 0
    self.imageWidth = Float(width)
    self.imageHeight = Float(height)
    self.mipLevels = Float(mipLevels)
  }
}
