import AstroStackApp
import Foundation
import ImageKit
import Observation
import ProcessKit
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Card 0058: the app's preprocessing on the PO's real targets, measured against the legacy runs
/// they were validated with — M 31 BB + DB (#78, the dual-band night marked) and IC 1848 (#79,
/// nebula mode). Through the window model as the Stacking stage drives it; per target a JSON
/// report (attachment `validation-e14-<target>.json`): wall time per step, peak scratch at step
/// boundaries, frames in and stacked per channel, the bundle's layers and the per-plane median /
/// MADN of each layer and of the legacy file it stands for, measured the same way. Nothing is
/// asserted beyond the run finishing: the comparison is read by the PO (docs/design/
/// validation-e14.md).
@MainActor
@Suite(
  "Live validation E14 — M 31 BB+DB and IC 1848 end to end, measured against #78 / #79",
  .liveFixtures, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
  .enabled(
    if: BuildConfiguration.optimized,
    "full targets of 26 MP frames need an optimized build: just test-heavy"),
  .serialized, .timeLimit(.minutes(120)))
struct LiveValidationE14Tests {
  /// One target: its captures, the mode, the night marked dual-band (as the PO did), the legacy
  /// run and the legacy files each bundle layer stands for.
  struct Target: Sendable, CustomTestStringConvertible {
    let name: String
    let captures: [String]
    let mode: PreprocessRequest.Mode
    let dualbandNight: String?
    let legacyRun: String
    var testDescription: String { name }
  }

  nonisolated static let targets = [
    Target(
      name: "m31-bb-db", captures: ["M31-DB", "M31-BB"], mode: .deepsky,
      dualbandNight: "2026-09-22", legacyRun: "M_31/20261018_191749"),
    Target(
      name: "ic1848", captures: ["IC1848"], mode: .nebula, dualbandNight: nil,
      legacyRun: "IC_1848/20261018_221220"),
  ]

  /// The legacy file a bundle layer stands for.
  nonisolated static let legacyFiles = [
    "RGB": "rgb_base.fits", "Ha": "syn_Ha.fits", "OIII": "syn_OIII.fits",
  ]

  @Test("measure the run against the legacy one", .scratchDirectory, arguments: targets)
  func testMeasure(target: Target) async throws {
    // The frame folders only: a capture folder may hold other things (a project package saved
    // there by mistake, found by this card: the scan walks into it).
    let captures = target.captures.flatMap { capture in
      ["lights", "darks", "flats", "bias"].map {
        ImportPlanning.capturesFolder.appendingPathComponent(capture).appendingPathComponent($0)
          .path
      }
    }
    guard captures.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else {
      try Test.cancel("captures \(target.captures) absent under ~/Documents/astro/captures")
    }
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(
      at: scratch.appendingPathComponent("\(target.name).astrostack"))
    defer { try? project.close() }
    let work = scratch.appendingPathComponent("work")
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      runs: RunServices(run: RunServices.live.run, scratch: work))
    var request = ImportRequest(paths: captures)
    let scanned = try await ImportPlanning.live(store: project.store)(request)
    if let night = target.dualbandNight {
      let set = try #require(
        scanned.inventory.sets.first { $0.key.type == .light && $0.key.session == night })
      request.filterSets[set.key.id] = .dualband
    }
    window.add(request)

    let started = Date()
    window.startRun(mode: target.mode)
    let run = try #require(window.run)
    let probe = RunProbe(work: work)
    probe.watch(run)
    await run.settled()
    let seconds = Date().timeIntervalSince(started)
    #expect(run.phase == .finished, "\(run.journalTail.map(\.text))")
    let result = try #require(run.result)

    let report = try Self.report(
      target: target, seconds: seconds, probe: probe, result: result,
      stack: project.url.appendingPathComponent("stacks/\(run.runID)"))
    let data = try JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    Attachment.record(data, named: "validation-e14-\(target.name).json")
  }

  /// The report of one run.
  static func report(
    target: Target, seconds: Double, probe: RunProbe, result: PreprocessResult, stack: URL
  ) throws -> [String: Any] {
    let legacyFolder = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Documents/astro/runs/\(target.legacyRun)")
    let legacyRun =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: legacyFolder.appendingPathComponent("run.json"))) as? [String: Any]
    var layers: [[String: Any]] = []
    for layer in result.bundle?.layers ?? [] {
      let ours = try FITSFile.read(at: stack.appendingPathComponent(layer.file)).image()
      var row: [String: Any] = [
        "id": layer.id, "width": ours.width, "height": ours.height,
        "planes": Self.planes(ours),
        "bundle_stats": ["bg": layer.stats.bg, "madn": layer.stats.madn],
      ]
      if let name = legacyFiles[layer.id] {
        let url = legacyFolder.appendingPathComponent(name)
        if let legacy = try? FITSFile.read(at: url).image() {
          row["legacy"] = [
            "file": name, "width": legacy.width, "height": legacy.height,
            "planes": Self.planes(legacy),
          ]
        }
      }
      layers.append(row)
    }
    let channels = try result.channels.map { channel -> [String: Any] in
      var row: [String: Any] = [
        "filter": channel.filter, "input_frames": channel.inputFrames,
        "stacked_frames": channel.stackedFrames, "warnings": channel.warnings,
        "error": channel.error ?? "",
      ]
      if let path = channel.masterPath {
        row["master"] = try Self.masters(
          ours: URL(fileURLWithPath: path),
          legacy: legacyFolder.appendingPathComponent("master_\(channel.filter).fits"))
      }
      return row
    }
    return [
      "target": target.name, "mode": "\(target.mode)", "seconds": seconds,
      "steps": probe.durations(), "peak_scratch_gb": Double(probe.peakBytes) / 1e9,
      "channels": channels, "layers": layers, "warnings": result.warnings,
      "crop": result.crop.map { "\($0)" } ?? "",
      "legacy": [
        "run": target.legacyRun, "channels": legacyRun?["channels"].map(Self.legacyChannels) ?? [],
        "timings": legacyRun?["timings"] ?? [], "combine_crop": legacyRun?["combine_crop"] ?? [:],
      ],
    ]
  }

  /// The stacked master beside the legacy one: sizes, per-plane statistics, and the mean |Δ| per
  /// plane in units of the legacy plane's MADN when the sizes match.
  static func masters(ours: URL, legacy: URL) throws -> [String: Any] {
    let mine = try FITSFile.read(at: ours).image()
    var row: [String: Any] = [
      "width": mine.width, "height": mine.height, "planes": Self.planes(mine),
    ]
    guard let theirs = try? FITSFile.read(at: legacy).image() else { return row }
    let legacyPlanes = Self.planes(theirs)
    row["legacy"] = [
      "file": legacy.lastPathComponent, "width": theirs.width, "height": theirs.height,
      "planes": legacyPlanes,
    ]
    if mine.width == theirs.width, mine.height == theirs.height,
      mine.planes.count == theirs.planes.count
    {
      // Siril's -output_norm rescales each master by its own min/max: the levels differ by an
      // affine map. Fit ours ≈ a·legacy + b per plane (every 7th pixel), then the residual's
      // MADN in units of our plane's MADN (1 ≈ independent noise of equal level, 0 = identical).
      row["affine_fit"] = zip(mine.planes, theirs.planes).map { pair -> [String: Double] in
        Self.affineFit(ours: pair.0, legacy: pair.1)
      }
    }
    return row
  }

  /// Least squares `ours ≈ a·legacy + b` on a 1/7 sample, the residual's MADN over ours, and
  /// the correlation.
  static func affineFit(ours: [Float], legacy: [Float]) -> [String: Double] {
    var (n, sx, sy, sxx, sxy, syy) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    for index in stride(from: 0, to: ours.count, by: 7) {
      let (x, y) = (Double(legacy[index]), Double(ours[index]))
      n += 1
      sx += x
      sy += y
      sxx += x * x
      sxy += x * y
      syy += y * y
    }
    let slope = (n * sxy - sx * sy) / max(n * sxx - sx * sx, 1e-30)
    let offset = (sy - slope * sx) / n
    let correlation =
      (n * sxy - sx * sy) / max(((n * sxx - sx * sx) * (n * syy - sy * sy)).squareRoot(), 1e-30)
    var residuals: [Double] = []
    var values: [Double] = []
    for index in stride(from: 0, to: ours.count, by: 7) {
      residuals.append(Double(ours[index]) - (slope * Double(legacy[index]) + offset))
      values.append(Double(ours[index]))
    }
    return [
      "a": slope, "b": offset, "correlation": correlation,
      "residual_madn_over_ours_madn": Self.madn(residuals) / max(Self.madn(values), 1e-30),
    ]
  }

  /// 1.4826 × the median absolute deviation.
  static func madn(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let median = sorted[sorted.count / 2]
    let deviations = values.map { abs($0 - median) }.sorted()
    return 1.4826 * deviations[deviations.count / 2]
  }

  /// Per plane: median and MADN, as the Studio measures a layer.
  static func planes(_ image: AstroImage) -> [[String: Double]] {
    StudioSession.stats(of: image).channels.map { ["median": $0.median, "madn": $0.madn] }
  }

  /// The legacy channels without their per-frame lists.
  static func legacyChannels(_ value: Any) -> [[String: Any]] {
    ((value as? [[String: Any]]) ?? []).map { channel in
      channel.filter { key, _ in
        ["filter", "input_frames", "stacked_frames", "covered_frac", "synthesized"].contains(key)
      }
    }
  }
}

/// Watches a run's steps (no polling): when each step starts and ends, and the scratch folder's
/// size at every transition — its peak is the report's disk figure.
@MainActor
final class RunProbe {
  private let work: URL
  private var started: [String: Date] = [:]
  private var ended: [String: Date] = [:]
  private(set) var peakBytes = 0

  init(work: URL) {
    self.work = work
  }

  func watch(_ run: RunViewModel) {
    record(run.steps)
    withObservationTracking {
      _ = run.steps
    } onChange: { [weak self] in
      Task { @MainActor in self?.watch(run) }
    }
  }

  /// Seconds per step title, in the order the steps began.
  func durations() -> [[String: Any]] {
    started.sorted { $0.value < $1.value }.map { title, start in
      ["step": title, "seconds": (ended[title] ?? Date()).timeIntervalSince(start)]
    }
  }

  private func record(_ steps: [RunViewModel.Step]) {
    let now = Date()
    for step in steps where !step.title.isEmpty {
      if step.state != .pending, started[step.title] == nil { started[step.title] = now }
      if step.state == .done || step.state == .failed, ended[step.title] == nil {
        ended[step.title] = now
      }
    }
    peakBytes = max(peakBytes, Self.size(of: work))
  }

  private static func size(of folder: URL) -> Int {
    let keys: [URLResourceKey] = [.fileAllocatedSizeKey]
    guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys)
    else { return 0 }
    var total = 0
    for case let file as URL in files {
      total += (try? file.resourceValues(forKeys: Set(keys)).fileAllocatedSize) ?? 0
    }
    return total
  }
}
