/// Why a folder does not open as a legacy run.
package enum LegacyRunError: Error, Equatable, Sendable {
  /// `run.json` is missing or unreadable.
  case notARun(String)
  /// A stack folder without its `bundle.json`.
  case noBundle(String)
  /// No layer file in the folder.
  case noLayers(String)
  /// Layers of different sizes: each layer and its size.
  case mixedDimensions([String])
}
