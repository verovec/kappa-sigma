package import Foundation
internal import ImageKit

/// Crops every colour-combine input to the field the stack covers cleanly (`applyEdgeCrop`).
///
/// It writes `out/trim_<tag>.fits`, all channels cut to their COMMON rectangle so the combine sees one
/// geometry. The masters and aligned files stay as the run recorded them.
package struct EdgeCropper: Sendable {
  /// What a measurement returns for one image: the clean rectangle, the cap flag, the full size.
  package struct Measurement: Equatable, Sendable {
    package var rect: EdgeRect
    package var capped: Bool
    package var width: Int
    package var height: Int

    /// A measurement.
    package init(rect: EdgeRect, capped: Bool, width: Int, height: Int) {
      self.rect = rect
      self.capped = capped
      self.width = width
      self.height = height
    }
  }
  /// Measures one combine input.
  package typealias Measure = @Sendable (URL) throws -> Measurement

  /// The applied crop, for the run record (`CombineCrop`).
  package struct Crop: Equatable, Sendable, Codable {
    package var rect: EdgeRect
    /// The kept fraction of the frame.
    package var fraction: Double
  }

  package var measure: Measure

  /// A cropper; `measure` reads the pixels unless a test substitutes a recorded verdict.
  package init(measure: @escaping Measure = Self.pixels) {
    self.measure = measure
  }

  /// The pixels' verdict through `EdgeTrim`.
  package static let pixels: Measure = { url in
    let image = try FITSFile.read(at: url).image()
    let (rect, capped) = EdgeTrim.measure(image.planes, width: image.width, height: image.height)
    return Measurement(rect: rect, capped: capped, width: image.width, height: image.height)
  }

  /// Crops `channels` (filter → basename in `out`); returns the channels to combine and the
  /// crop applied (nil: nothing cut, the input returned).
  package func apply(_ channels: [String: String], out: URL, journal: inout PreprocessJournal)
    -> (channels: [String: String], crop: Crop?)
  {
    guard !channels.isEmpty else { return (channels, nil) }
    var common: EdgeRect?
    var full = EdgeRect(x0: 0, y0: 0, x1: 0, y1: 0)
    var capped = false
    for base in channels.values.sorted() {
      do {
        let measured = try measure(out.appendingPathComponent(base + ".fits"))
        capped = capped || measured.capped
        full = EdgeRect(x0: 0, y0: 0, x1: measured.width, y1: measured.height)
        common = common?.intersect(measured.rect) ?? measured.rect
      } catch {
        journal.warn("edge trim skipped: \(ChannelStacker.describe(error))")
        return (channels, nil)
      }
    }
    guard let common, common.width > 0, common.height > 0 else {
      journal.warn("edge trim skipped: the channels share no clean field")
      return (channels, nil)
    }
    if capped {
      journal.warn(
        "the stack's ragged edge reaches past \(Int((EdgeTrim.maxTrimFraction * 100).rounded()))% "
          + "of the frame — trimming that much and no more; the sky model may still see a step")
    }
    guard common != full else { return (channels, nil) }
    return crop(channels, to: common, full: full, out: out, journal: &journal)
  }

  private func crop(
    _ channels: [String: String], to common: EdgeRect, full: EdgeRect, out: URL,
    journal: inout PreprocessJournal
  ) -> (channels: [String: String], crop: Crop?) {
    var cropped: [String: String] = [:]
    for (filter, base) in channels.sorted(by: { $0.key < $1.key }) {
      let name = "trim_" + ChannelTag.of(filter)
      do {
        try FITSFile.read(at: out.appendingPathComponent(base + ".fits")).writeCrop(
          to: out.appendingPathComponent(name + ".fits"), x0: common.x0, y0: common.y0,
          x1: common.x1, y1: common.y1)
        cropped[filter] = name
      } catch {
        journal.warn(
          "edge trim failed on \(filter) (\(ChannelStacker.describe(error))) — combining uncropped")
        return (channels, nil)
      }
    }
    let (right, bottom) = (full.x1 - common.x1, full.y1 - common.y1)
    journal.line(
      "✂ trimmed the stacking edge: \(full.width)×\(full.height) → "
        + "\(common.width)×\(common.height) px (left \(common.x0), right \(right), "
        + "top \(common.y0), bottom \(bottom))")
    let fraction = Double(common.area) / Double(max(1, full.area))
    return (cropped, Crop(rect: common, fraction: fraction))
  }
}
