package import Foundation
internal import ImageKit

/// Crops every combine input to the field ALL channels cover (`applyCoverageCrop`): channels
/// stacked from different nights cover different rotated footprints, and combining them as they
/// are paints regional colour casts and black wedges. `combine_<tag>.fits` copies; the aligned
/// files stay as they were.
package enum CoverageCrop {
  /// Under this fraction of the canvas the nights barely intersect: the full field is kept.
  static let minimumRectangle = 0.35

  /// The crop, for the run record (`CombineCrop`).
  package struct Record: Equatable, Sendable {
    package var rect: EdgeRect
    package var fraction: Double
    package var applied = false
    package var note = ""
  }

  /// Crops `channels` (filter → basename in `out`) to the common rectangle of `grids`; returns
  /// the channels to combine and the record (nil when no channel carries coverage).
  package static func apply(
    _ channels: [String: String], grids: [String: CoverageGrid], minimumFraction: Double, out: URL,
    journal: inout PreprocessJournal
  ) -> (channels: [String: String], record: Record?) {
    let used = grids.filter { channels[$0.key] != nil }.sorted { $0.key < $1.key }
    guard let first = used.first?.value,
      let common = intersect(used.map { $0.value.mask(minimumFraction: minimumFraction) })
    else { return (channels, nil) }
    let cells = largestRectangle(common, width: first.width, height: first.height)
    let fraction = Double(cells.area) / Double(first.width * first.height)
    let scale = first.scale
    var record = Record(
      rect: EdgeRect(
        x0: cells.x0 * scale, y0: cells.y0 * scale, x1: cells.x1 * scale, y1: cells.y1 * scale),
      fraction: fraction)
    if fraction < minimumRectangle {
      record.note =
        "common coverage rectangle is only \(Int((fraction * 100).rounded()))% of the canvas "
        + "— keeping the full field"
      journal.warn("coverage crop skipped: " + record.note)
      return (channels, record)
    }
    guard record.rect.width > 0, record.rect.height > 0, fraction <= 0.98 else {
      return (channels, record)
    }
    var cropped: [String: String] = [:]
    for (filter, base) in channels.sorted(by: { $0.key < $1.key }) {
      let name = "combine_" + ChannelTag.of(filter)
      do {
        try FITSFile.read(at: out.appendingPathComponent(base + ".fits")).writeCrop(
          to: out.appendingPathComponent(name + ".fits"), x0: record.rect.x0, y0: record.rect.y0,
          x1: record.rect.x1, y1: record.rect.y1)
        cropped[filter] = name
      } catch {
        journal.warn(
          "coverage crop failed on \(filter) (\(ChannelStacker.describe(error))) "
            + "— combining uncropped"
        )
        return (channels, record)
      }
    }
    record.applied = true
    journal.line(
      "✂ combine cropped to the common covered field \(record.rect.width)×\(record.rect.height) px "
        + "(\(Int((fraction * 100).rounded()))% of canvas)")
    return (cropped, record)
  }

  /// The AND of same-size masks; nil when empty or the sizes disagree.
  static func intersect(_ masks: [[Bool]]) -> [Bool]? {
    guard var out = masks.first, masks.allSatisfy({ $0.count == out.count }) else { return nil }
    for mask in masks.dropFirst() { out = zip(out, mask).map { $0 && $1 } }
    return out
  }

  /// The largest all-true rectangle of a w×h mask, in cells (`largestInteriorRect`, histogram
  /// method; the first maximal one wins).
  package static func largestRectangle(_ mask: [Bool], width: Int, height: Int) -> EdgeRect {
    var heights = [Int](repeating: 0, count: width)
    var best = EdgeRect(x0: 0, y0: 0, x1: 0, y1: 0)
    for row in 0..<height {
      for column in 0..<width {
        heights[column] = mask[row * width + column] ? heights[column] + 1 : 0
      }
      var stack: [(start: Int, height: Int)] = []
      for column in 0...width {
        let bar = column < width ? heights[column] : 0
        var start = column
        while let top = stack.last, top.height >= bar {
          stack.removeLast()
          if top.height * (column - top.start) > best.area {
            best = EdgeRect(x0: top.start, y0: row - top.height + 1, x1: column, y1: row + 1)
          }
          start = top.start
        }
        if bar > 0 { stack.append((start, bar)) }
      }
    }
    return best
  }
}
