internal import Foundation

/// The memory gate of the cross-frame mask and the seam noise pass (`transient/budget.go`,
/// `trailBasisPlan`).
///
/// The in-memory mask holds every registered frame and a residual plane per frame; above the
/// budget it streams one frame at a time against an evenly spaced basis instead of exhausting
/// the machine.
package enum TrailMaskBudget {
  /// The override, in GiB.
  package static let environmentKey = "ASTRO_TRAIL_MASK_MEM_GB"

  /// The byte budget: the override when set and positive, else half the physical memory (the
  /// Siril peaks are sequential with these passes).
  package static func bytes(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
  ) -> Int64 {
    if let text = environment[environmentKey], let gib = Double(text), gib > 0 {
      return Int64(gib * Double(1 << 30))
    }
    return Int64(physicalMemory / 2)
  }

  /// In memory while 3·n·frame fits the budget (each frame plus its residual, with slack);
  /// otherwise streamed with budget / (2·frame) − 6 basis frames, kept within [16, 48] and ≤ n.
  /// `frameBytes` is a whole frame, every plane of it; 0 (unknown) keeps the in-memory pass.
  package static func plan(frames: Int, frameBytes: Int64, budget: Int64) -> (
    streamed: Bool, basis: Int
  ) {
    guard frameBytes > 0, 3 * Int64(frames) * frameBytes > budget else { return (false, 0) }
    return (true, min(max(Int(budget / (2 * frameBytes)) - 6, 16), 48, frames))
  }

  /// `count` evenly spaced indices over 0..<`total` (all of them when `count` ≥ `total`).
  package static func evenIndices(_ total: Int, _ count: Int) -> [Int] {
    count >= total ? Array(0..<total) : (0..<count).map { $0 * total / count }
  }
}
