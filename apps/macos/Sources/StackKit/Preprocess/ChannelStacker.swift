package import Foundation
internal import ImageKit

/// Turns one light set into its linear channel master (`processChannel` +
/// `finishStackedChannel`, single night): link → calibrate + register → grade → stack the
/// survivors → strip a spurious BAYERPAT.
///
/// A channel that fails is an outcome with an `error`, never the end of the run; cancellation is.
package struct ChannelStacker: Sendable {
  /// The trail verdict of a calibrated frame, given its file and the downsampled size.
  package typealias TrailProbe =
    @Sendable (_ frame: URL, _ size: Int) -> (detected: Bool, score: Double)?

  package var runner: SirilRunner
  package var settings: PreprocessSettings
  package var trailProbe: TrailProbe
  /// Live journal: Siril's lines and the channel's `⚠` warnings.
  package var report: @Sendable (String) -> Void

  /// A stacker; trails are probed on the pixels unless a test substitutes them.
  package init(
    runner: SirilRunner, settings: PreprocessSettings = PreprocessSettings(),
    trailProbe: @escaping TrailProbe = Self.pixelTrail,
    report: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.runner = runner
    self.settings = settings
    self.trailProbe = trailProbe
    self.report = report
  }

  /// The pixels' verdict: the frame max-pooled to `size`, through `TrailDetector`.
  package static let pixelTrail: TrailProbe = { frame, size in
    guard let file = try? FITSFile.read(at: frame),
      let reduced = try? file.downsampled(maxDimension: size, pooling: .max)
    else { return nil }
    let verdict = TrailDetector.detect(reduced.grid, width: reduced.width, height: reduced.height)
    return (verdict.detected, verdict.score)
  }

  /// Stacks `set` as channel `filter`: frames linked under `work/light_<lane>`, the master
  /// written to `out/master_<tag>.fits`.
  package func stack(
    _ set: FrameSet, filter: String, inventory: Inventory, masters: [CalibrationMaster],
    work: URL, out: URL
  ) async throws -> ChannelOutcome {
    let selection = CalibrationMatcher.select(set, in: inventory, masters: masters)
    var outcome = ChannelOutcome(set, filter: filter, selection: selection)
    let folder = work.appendingPathComponent("light_" + ChannelTag.sanitize(filter))
    // Siril's `link` takes every FITS in the folder: a previous run's frames must not be there,
    // and the bulky calibrated copies go even when the run is cancelled.
    try? FileManager.default.removeItem(at: folder)
    defer { try? FileManager.default.removeItem(at: folder) }
    do {
      try MasterBuilder.link(set.frames.map(\.path), into: folder)
      let light = Light(
        folder: folder, masters: Self.masters(selection, frames: set.frames),
        ingest: SirilIngest(paths: set.frames.map(\.path)))
      if set.count == 1 {
        try await promoteLone(light, into: &outcome, out: out)
      } else {
        try await calibrateRegister(light, into: &outcome)
        try await gradeAndStack(light, frames: set.frames, into: &outcome, out: out)
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      outcome.error = Self.describe(error)
    }
    return outcome
  }

  /// A channel's working sequence.
  struct Light {
    let folder: URL
    let masters: CalibrationMasters
    let ingest: SirilIngest
    let seq = "light"
    /// The calibrated sequence (`pp_light` or `light`).
    var calibrated: String { SirilScripts.calibrated(seq, masters: masters) }
    /// The registered sequence.
    var registered: String { "r_" + calibrated }

    func frame(_ sequence: String, _ index: Int) -> URL {
      folder.appendingPathComponent(sequence + String(format: "_%05d.fits", index))
    }
  }

  /// What `calibrate` applies: the selection, the dark's defect map when one sits beside it, and
  /// CFA-aware calibration when every frame is still a mosaic.
  static func masters(_ selection: CalibrationSelection, frames: [CaptureFrame])
    -> CalibrationMasters
  {
    var masters = selection.masters
    masters.badPixelMap = selection.dark.flatMap { defectList(of: $0.path) }
    masters.cfa = !frames.isEmpty && frames.allSatisfy(\.needsDebayer)
    return masters
  }

  /// The dark's `<name>_defects.lst` sidecar, when it exists (`DefectsListFor`).
  static func defectList(of master: String) -> String? {
    guard !master.isEmpty else { return nil }
    let path = (master as NSString).deletingPathExtension + "_defects.lst"
    return FileManager.default.fileExists(atPath: path) ? path : nil
  }

  /// Runs `script` in `folder`, Siril's lines to the journal.
  func run(_ script: SirilScript, in folder: URL) async throws {
    let report = report
    _ = try await runner.run(script, folder) { report($0.text) }
  }

  func warn(_ message: String, into outcome: inout ChannelOutcome) {
    outcome.warnings.append(message)
    report("⚠ " + message)
  }

  static func describe(_ error: any Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
  }
}
