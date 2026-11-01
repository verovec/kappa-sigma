internal import ImageKit

/// What a chain preview starts from, kept for the drags of one edit (card 0158).
///
/// Step `k`'s input and the recorded masks of the steps from it to `end`, read over the history's step
/// `files`.
struct ChainInput {
  /// The step the chain starts from.
  let k: Int
  /// The step it stops before (the first host tool), or the step count.
  let end: Int
  /// The history's step files when it was read: any other set reads it again.
  let files: [String]
  /// What step `k` reads.
  let state: ChainState
  /// The recorded mask of each masked step from `k`, by index.
  let masks: [Int: AstroImage]
}
