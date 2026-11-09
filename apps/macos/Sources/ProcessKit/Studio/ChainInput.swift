internal import ImageKit

// MARK: - The cached input of a chain preview (card 0158)

/// The input of step k and the recorded masks of the steps from k to end, on the GPU.
///
/// Read over the history's step `files` and uploaded once (card 0188): a drag re-renders the
/// chain, not the disk reads nor the uploads.
struct ChainInput {
  /// The step the chain starts from.
  let k: Int
  /// The step it stops before (the first host tool), or the step count.
  let end: Int
  /// The history's step files when it was read: any other set reads it again.
  let files: [String]
  /// What step `k` reads.
  let state: ChainState
  /// The recorded mask of each masked step from `k`, by index, on the GPU.
  let masks: [Int: GPUImage]
}
