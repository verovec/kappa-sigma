package import ImageKit
package import Metal

/// An image a process reads and writes on the GPU: one `r32Float` texture per plane, shared
/// storage so Apply reads the result back without a blit.
package final class GPUImage {
  /// One texture per plane (1 or 3).
  package let planes: [MTLTexture]
  /// Width in pixels.
  package let width: Int
  /// Height in pixels.
  package let height: Int

  /// A zeroed image of `channels` planes.
  package init(device: MTLDevice, width: Int, height: Int, channels: Int) throws {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .shared
    planes = try (0..<channels).map { _ in
      guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw ProcessError.commandFailed("texture \(width)×\(height)")
      }
      return texture
    }
    self.width = width
    self.height = height
  }

  /// `planes` (`planes[c][y * width + x]`) uploaded.
  package convenience init(device: MTLDevice, width: Int, height: Int, planes: [[Float]]) throws {
    guard planes.allSatisfy({ $0.count == width * height }) else { throw ProcessError.sizeMismatch }
    try self.init(device: device, width: width, height: height, channels: planes.count)
    for (texture, plane) in zip(self.planes, planes) {
      unsafe plane.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return }
        unsafe texture.replace(
          region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base,
          bytesPerRow: width * MemoryLayout<Float>.stride)
      }
    }
  }

  /// `image`'s planes uploaded.
  package convenience init(device: MTLDevice, image: AstroImage) throws {
    try self.init(device: device, width: image.width, height: image.height, planes: image.planes)
  }

  /// A zeroed image of the same size and plane count.
  package func sameSize(device: MTLDevice) throws -> GPUImage {
    try GPUImage(device: device, width: width, height: height, channels: planes.count)
  }

  /// The planes read back (after the commands writing them completed).
  package func read() -> [[Float]] {
    planes.map { texture in
      unsafe [Float](unsafeUninitializedCapacity: width * height) { buffer, count in
        guard let base = buffer.baseAddress else { return }
        unsafe texture.getBytes(
          base, bytesPerRow: width * MemoryLayout<Float>.stride,
          from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        count = width * height
      }
    }
  }
}
