package import ImageKit

/// What a step made on the GPU (card 0188): its image with the metadata it carries, its role
/// outputs and the bundle layers it rewrote — nothing read back.
package struct GPUStep {
  /// The step's image.
  package let result: GPUImage
  /// Its metadata: the input's, with the plate solution moved by a geometric step.
  package let metadata: ImageMetadata
  /// The layers moved as the step's outputs of the roles earlier steps wrote.
  package let outputs: [LayerRole: GPUImage]
  /// The bundle layers moved, replaced for the steps after.
  package let replacing: [String: GPUImage]

  /// The step's image as the next step's input.
  package var input: (image: GPUImage, metadata: ImageMetadata) { (result, metadata) }
}
