internal import Foundation
internal import ImageKit

/// The defective pixels of a sensor, from a master dark's raw pool (`calib/defects.go`).
///
/// Per pixel, the temporal mean and sigma across the darks, against a local 5×5 separable median
/// baseline (amp glow is never a defect): hot/cold when the mean is > 3 robust σ off, unstable
/// (telegraph) when the sigma is > 6 robust σ above. Written as Siril's `P x y H|C` list beside
/// the master and applied per light with `calibrate -cc=bpm`.
package struct DarkDefects: Equatable, Sendable {
  /// One flagged pixel, in the frames' own row order.
  package struct Pixel: Equatable, Sendable {
    package var x: Int
    package var y: Int
    /// `H` (hot or unstable: repaired alike) or `C` (cold).
    package var kind: Character
    /// `h`, `c` or `u`: the counts split.
    var category: Character
    /// Detection strength in robust sigmas: the cap keeps the strongest.
    var severity: Double
  }

  static let minimumFrames = 8
  static let sigmaK = 3.0
  static let unstableK = 6.0
  static let maxFraction = 0.005
  static let statSample = 200_000

  package var width: Int
  package var height: Int
  /// The frames are ROWORDER=TOP-DOWN: y is flipped in Siril's (bottom-up) list.
  package var topDown: Bool
  package var pixels: [Pixel] = []
  package var truncated = false

  /// An empty list for a `width` × `height` sensor.
  package init(width: Int, height: Int, topDown: Bool) {
    self.width = width
    self.height = height
    self.topDown = topDown
  }

  package var hot: Int { pixels.count { $0.category == "h" } }
  package var cold: Int { pixels.count { $0.category == "c" } }
  package var unstable: Int { pixels.count { $0.category == "u" } }

  /// `N hot, N cold, N unstable px[ (capped)]`.
  package var summary: String {
    "\(hot) hot, \(cold) cold, \(unstable) unstable px" + (truncated ? " (capped)" : "")
  }

  /// The sidecar of a master dark: `<master>_defects.lst`.
  package static func listPath(of master: String) -> String {
    (master as NSString).deletingPathExtension + "_defects.lst"
  }

  /// Siril's list (`P x y H|C`, 0-based, y flipped for TOP-DOWN frames).
  package var sirilList: String {
    pixels.map { "P \($0.x) \(topDown ? height - 1 - $0.y : $0.y) \($0.kind)\n" }.joined()
  }

  /// Scans `frames`, writes the list beside `master` (or removes a stale one when there is
  /// nothing to list); returns the run note, nil when silent (`buildDefectList`).
  package static func build(master: String, frames: [String]) -> String? {
    let list = listPath(of: master)
    guard let defects = scan(frames), !defects.pixels.isEmpty else {
      try? FileManager.default.removeItem(atPath: list)
      return nil
    }
    do {
      try Data(defects.sirilList.utf8).write(to: URL(fileURLWithPath: list), options: .atomic)
    } catch {
      return "dark defect map skipped: \(error)"
    }
    return "dark defect map: \(defects.summary) → per-frame cosmetic repair via -cc=bpm"
  }

  /// The temporal statistics of the readable mono frames sharing the first one's size; nil under
  /// eight frames (`ScanDarkDefects`).
  package static func scan(_ frames: [String]) -> Self? {
    var sum: [Double] = []
    var squares: [Double] = []
    var (width, height, used, topDown) = (0, 0, 0, false)
    for path in frames {
      guard let file = try? FITSFile.read(at: URL(fileURLWithPath: path)),
        let image = try? file.image(),
        image.planes.count == 1
      else { continue }
      if used == 0 {
        (width, height) = (image.width, image.height)
        topDown = file.header.string("ROWORDER")?.uppercased() == "TOP-DOWN"
        sum = Array(repeating: 0, count: width * height)
        squares = sum
      } else if image.width != width || image.height != height {
        continue
      }
      for (index, value) in image.planes[0].enumerated() {
        let double = Double(value)
        sum[index] += double
        squares[index] += double * double
      }
      used += 1
    }
    guard used >= minimumFrames else { return nil }
    let count = Double(used)
    let means = sum.map { Float($0 / count) }
    let sigmas = zip(sum, squares).map { total, square in
      let mean = total / count
      return Float(max(0, square / count - mean * mean).squareRoot())
    }
    var defects = Self(width: width, height: height, topDown: topDown)
    defects.flag(means: means, sigmas: sigmas)
    return defects
  }
}
