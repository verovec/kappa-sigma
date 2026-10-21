package import Metal

/// GPU-only intermediates of multi-pass kernels (morphology, box blurs).
package enum ScratchTexture {
  /// A private `r32Float` texture the size of `input`, for kernels to read and write.
  package static func make(like input: MTLTexture, device: MTLDevice) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r32Float, width: input.width, height: input.height, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .private
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw ProcessError.commandFailed("scratch texture \(input.width)×\(input.height)")
    }
    return texture
  }
}
