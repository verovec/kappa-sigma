import Foundation
import Metal
import RenderKit

/// The test GPU: the system device, or `nil` (CI runners may have none) — GPU suites skip then.
enum GPU {
  static let device = MTLCreateSystemDefaultDevice()
  static var available: Bool { device != nil }

  /// A one-plane r32Float texture of `values` (row-major).
  static func texture(_ values: [Float], width: Int, height: Int) throws -> ImageTexture {
    let device = try requireDevice()
    return try ImageTexture(device: device, width: width, height: height, planes: [values])
  }

  static func requireDevice() throws -> MTLDevice {
    guard let device else { throw GPUTestError.noDevice }
    return device
  }

  /// An rgba32Float texture the display kernel can write and the test can read.
  static func output(width: Int, height: Int) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
    descriptor.usage = [.shaderWrite, .shaderRead]
    descriptor.storageMode = .shared
    guard let texture = try requireDevice().makeTexture(descriptor: descriptor) else {
      throw GPUTestError.noTexture
    }
    return texture
  }

  /// The RGBA pixels of an rgba32Float texture.
  static func read(_ texture: MTLTexture) -> [SIMD4<Float>] {
    var pixels = [SIMD4<Float>](repeating: .zero, count: texture.width * texture.height)
    pixels.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress else { return }
      texture.getBytes(
        base, bytesPerRow: texture.width * 16,
        from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
    }
    return pixels
  }
}

enum GPUTestError: Error {
  case noDevice, noTexture
}
