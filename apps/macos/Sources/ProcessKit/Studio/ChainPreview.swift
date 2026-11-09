package import ImageKit

/// What the chain preview of a revised step shows (card 0158): the image the chain ends on, and
/// the host-tool step it stopped before, if any (that step runs at the revise, not live).
package struct ChainPreview {
  /// The output of the last step rendered, or the input of `stoppedBefore`.
  package let image: AstroImage
  /// The index of the first host-tool step of the chain, or `nil` when it rendered to the head.
  package let stoppedBefore: Int?
  /// Rendered on a proxy (card 0189): the full size, not the full pixels — said to the user.
  package let reduced: Bool
}
