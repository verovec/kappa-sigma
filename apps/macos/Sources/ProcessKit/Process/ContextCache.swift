internal import Foundation

/// What `StepRunner` built last, so a preview frame reuses it: the uploaded context, by the
/// history folder and the files overlaid.
final class ContextCache {
  /// What a context was built from.
  struct Key: Equatable {
    let directory: URL
    let files: [String: String]
  }

  /// The last context.
  var entry: (key: Key, layers: [String: GPUImage], stats: [String: LayerStats])?
}
