/// The per-tile noise sigmas of a first detail plane (`tileSigmaGrid`).
struct TileSigmaGrid {
  /// The clamped per-tile sigmas, row-major.
  let grid: [Double]
  /// The grid width in tiles.
  let gridWidth: Int
  /// The grid height in tiles.
  let gridHeight: Int
  /// The median tile sigma σ_G.
  let sigma: Double
  /// The 90th percentile of the unclamped tile sigmas.
  let p90: Double
}
