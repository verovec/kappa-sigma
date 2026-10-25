/// Which bundle layers a process may edit on its own branch (card 0118), before the layers are
/// combined: only a process whose output depends on its input alone, at the same size, on linear
/// data — a branch never moves pixels (one canvas: co-registration must hold).
package enum BranchUse: String, Sendable {
  /// Main history only.
  case never
  /// Any layer: a line (one plane) or the colour image.
  case anyLayer
  /// Colour layers only (three planes): colour balance, colour calibration.
  case colourLayers
}
