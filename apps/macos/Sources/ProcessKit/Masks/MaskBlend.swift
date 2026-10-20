package import Metal

/// The kit's generic mask pass.
///
/// out = mask · processed + (1 − mask) · input, per plane. Apply (`ProcessRunner`) and a live
/// preview encode the same pass, so a masked preview equals Apply.
package struct MaskBlend {
  private let pipeline: MTLComputePipelineState

  /// The blend pass on `device`.
  package init(device: MTLDevice) throws {
    pipeline = try ProcessLibrary.pipeline(
      device: device, file: "Mask.metal", function: "maskBlend")
  }

  /// Encodes the blend into `commands`; `mask` is one plane of the image's size, `input` may have
  /// fewer planes than `output` (a mono input under an RGB-producing process repeats its plane).
  package func encode(
    into commands: MTLCommandBuffer, input: GPUImage, processed: GPUImage, mask: GPUImage,
    output: GPUImage
  ) throws {
    guard mask.width == output.width, mask.height == output.height,
      input.width == output.width, input.height == output.height
    else { throw ProcessError.sizeMismatch }
    for plane in 0..<output.planes.count {
      guard let encoder = commands.makeComputeCommandEncoder() else {
        throw ProcessError.commandFailed("mask blend encoder")
      }
      encoder.setComputePipelineState(pipeline)
      encoder.setTexture(input.planes[min(plane, input.planes.count - 1)], index: 0)
      encoder.setTexture(processed.planes[plane], index: 1)
      encoder.setTexture(mask.planes[0], index: 2)
      encoder.setTexture(output.planes[plane], index: 3)
      MaskBuilder.dispatch(encoder, over: output)
    }
  }
}
