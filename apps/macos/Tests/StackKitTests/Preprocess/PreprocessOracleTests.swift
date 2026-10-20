import Foundation
import StackKit
import TestSupport
import Testing

/// The run against the legacy engine's recording of 0044 case (a), the synthetic single night:
/// Siril is played back (each registration writes the recorded metrics as its `.seq`) and the
/// pixel decisions are the recorded ones, so what is compared is everything this port decides —
/// the scripts, in order and byte for byte, the frame selection and the registration references.
@Suite("Preprocess oracle — the synthetic single night against the legacy recording")
struct PreprocessOracleTests {
  static let runID = "RUNID48"

  /// The recorded grades as a `.seq` per light folder, and the recorded trail verdicts.
  struct Playback: Sendable {
    let sequences: [String: String]
    let trails: [String: [(Bool, Double)]]

    init(_ grades: [OracleChannelGrades]) {
      var sequences: [String: String] = [:]
      var trails: [String: [(Bool, Double)]] = [:]
      for channel in grades {
        let folder = "light_" + channel.filter
        sequences[folder] = channel.metrics.map { metric in
          let (dx, dy) = (metric.shiftX ?? 0, metric.shiftY ?? 0)
          return "R0 \(metric.fwhm) \(metric.wfwhm) \(metric.roundness) \(metric.quality) "
            + "\(metric.background) \(metric.starCount) H 1 0 \(dx) 0 1 \(dy) 0 0 1"
        }.joined(separator: "\n")
        trails[folder] = channel.metrics.map { ($0.trailDetected, $0.trailScore ?? 0) }
      }
      self.sequences = sequences
      self.trails = trails
    }

    /// The verdict for `pp_light_0000N.fits` in `light_<F>`.
    func trail(_ frame: URL) -> (detected: Bool, score: Double)? {
      let index = Int(frame.deletingPathExtension().lastPathComponent.suffix(5)) ?? 0
      guard let verdicts = trails[frame.deletingLastPathComponent().lastPathComponent],
        index >= 1, index <= verdicts.count
      else { return nil }
      return verdicts[index - 1]
    }
  }

  /// Runs the golden case; returns the Siril double and the result.
  static func run(root: URL, oracle: OracleCase) async throws -> (PipelineSiril, PreprocessResult) {
    let inventory = try MasterBuilderTests.scan(oracle.manifest.caseName, under: root)
    let playback = Playback(try oracle.grades())
    let siril = PipelineSiril(sequence: { playback.sequences[$0] })
    let tools = Preprocessor.Tools(
      runner: siril.runner, trailProbe: { frame, _ in playback.trail(frame) },
      // The recorded run hit the 12% cap (run.json warnings); the rectangle itself is pixels.
      edgeMeasure: { _ in (EdgeRect(x0: 30, y0: 30, x1: 226, y1: 226), true, 256, 256) })
    let request = PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/TESTFIELD/\(runID)"),
      work: root.appendingPathComponent("work/run_\(runID)"), runID: runID)
    let result = try await Preprocessor(tools: tools).perform(request) { _ in }
    return (siril, result)
  }

  static func normalize(_ text: String, root: URL) -> String {
    text.replacingOccurrences(of: root.path, with: "<ROOT>").replacingOccurrences(of: runID, with: "<RUN>")
  }

  @Test("scripts byte-equal in order; kept/rejected frames, references and warnings as recorded", .scratchDirectory)
  func testSingleNightScriptsAndSelection() async throws {
    let oracle = try OracleFixtureTests.committedCase("golden-single-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let (siril, result) = try await Self.run(root: root, oracle: oracle)

    // The legacy finish (autostretch, GIMP, exports) is the Studio's now: scripts up to the
    // neutralized composite are this card's.
    let recorded = try oracle.scripts().filter { $0.number <= 18 }
    let ours = siril.calls.map { (Self.normalize($0.directory.lastPathComponent, root: root), Self.normalize($0.script, root: root)) }
    #expect(ours.map(\.0) == recorded.map(\.directory))
    for (index, script) in recorded.enumerated() where index < ours.count {
      #expect(ours[index].1 == script.text, "script \(script.name)")
    }

    let selection = try oracle.selection()
    #expect(result.channels.map(\.filter) == selection.channels.map(\.filter))
    for (channel, recordedChannel) in zip(result.channels, selection.channels) {
      #expect(channel.kept.map { Self.normalize($0, root: root) } == recordedChannel.kept)
      let rejected = channel.grades.filter(\.rejected).map { Self.normalize($0.path, root: root) }
      #expect(rejected == recordedChannel.rejected.map(\.path))
      #expect(channel.stackedFrames == recordedChannel.stackedFrames)
      #expect(channel.inputFrames == recordedChannel.inputFrames)
    }
    #expect(selection.unselect.isEmpty == !siril.calls.contains { $0.script.contains("unselect") })
    let registration = try oracle.registration()
    let setrefs = siril.calls.flatMap { $0.script.split(separator: "\n").filter { $0.hasPrefix("setref") } }
    #expect(setrefs.map(String.init) == registration.setref.map(\.command))
    #expect(registration.channels.allSatisfy { $0.preRejected.isEmpty })
    let warnings = try oracle.run().warnings ?? []
    #expect(result.warnings == warnings)
  }
}
