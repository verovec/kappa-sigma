internal import Foundation
internal import ImageKit

/// What `StepRunner` built last, so a preview frame reuses it: the uploaded context by the
/// history folder and the files overlaid, and the head's header by its file.
final class ContextCache {
  /// What a context was built from.
  struct Key: Equatable {
    let directory: URL
    let files: [String: String]
  }

  /// Which head a header was read from.
  struct HeadKey: Equatable {
    let directory: URL
    let file: String?
  }

  /// The last context.
  var entry: (key: Key, layers: [String: GPUImage], stats: [String: LayerStats])?
  /// The last head header.
  var head: (key: HeadKey, header: FITSHeader?)?
}
