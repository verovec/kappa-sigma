internal import ImageKit
package import Metal

/// An image on the GPU: one `r32Float` texture per plane, with the ImageKit pyramid's 2×2 block
/// means as mip levels (the GPU's own mip generation is not used: the levels must match the
/// pyramid the CPU side measures).
package final class ImageTexture {
  /// One texture per plane (1 or 3).
  package let planes: [MTLTexture]
  /// Width in pixels.
  package let width: Int
  /// Height in pixels.
  package let height: Int
  /// Number of mip levels (level 0 is full resolution).
  package let mipLevels: Int

  /// Uploads `planes` (`planes[c][y * width + x]`, rows top-down as displayed).
  package init(device: MTLDevice, width: Int, height: Int, planes: [[Float]]) throws {
    let pyramid = Pyramid(width: width, height: height, planes: planes, smallestSide: 1)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r32Float, width: width, height: height, mipmapped: true)
    descriptor.mipmapLevelCount = pyramid.levels.count
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    self.planes = try planes.indices.map { index in
      guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw RenderError.textureAllocationFailed(width: width, height: height)
      }
      for (level, mip) in pyramid.levels.enumerated() {
        mip.planes[index].withUnsafeBytes { bytes in
          guard let base = bytes.baseAddress else { return }
          texture.replace(
            region: MTLRegionMake2D(0, 0, mip.width, mip.height), mipmapLevel: level,
            withBytes: base, bytesPerRow: mip.width * MemoryLayout<Float>.stride)
        }
      }
      return texture
    }
    self.width = width
    self.height = height
    self.mipLevels = pyramid.levels.count
  }
}
