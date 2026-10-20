import Foundation
import StackKit
import TestSupport
import Testing

/// The `Preprocessor` actor over a Siril double: ordered step events, previews, cancellation that
/// keeps finished masters and writes no bundle, one run per output folder.
@Suite("Preprocessor — events, previews, cancel, one run per target")
struct PreprocessorTests {
  static func request(_ run: String = "R1") throws -> PreprocessRequest {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let inventory = try MasterBuilderTests.scan("golden-single-night", under: root)
    return PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/TESTFIELD/\(run)"),
      work: root.appendingPathComponent("work/run_\(run)"), runID: run)
  }

  static func tools(_ siril: PipelineSiril) -> Preprocessor.Tools {
    Preprocessor.Tools(
      runner: siril.runner, trailProbe: { _, _ in (false, 0.1) },
      edgeMeasure: { _ in
        .init(
          rect: EdgeRect(x0: 8, y0: 0, x1: 256, y1: 250), capped: false, width: 256, height: 256)
      })
  }

  /// Every event of a run, and its error.
  static func collect(_ stream: AsyncThrowingStream<PreprocessEvent, any Error>) async
    -> ([PreprocessEvent], (any Error)?)
  {
    var events: [PreprocessEvent] = []
    do {
      for try await event in stream { events.append(event) }
      return (events, nil)
    } catch {
      return (events, error)
    }
  }

  static func isFinished(_ event: PreprocessEvent) -> Bool {
    if case .finished = event { return true }
    return false
  }

  @Test(
    "ordered step events, previews, the finished bundle; cancel keeps masters, no bundle",
    .scratchDirectory)
  func testEventsAndCancel() async throws {
    let (events, error) = await Self.collect(
      Preprocessor(tools: Self.tools(PipelineSiril())).run(try Self.request()))
    #expect(error == nil)
    let titles = events.compactMap { event -> String? in
      guard case .progress(let progress) = event, progress.line.isEmpty else { return nil }
      return "\(progress.step)/\(progress.steps) \(progress.title)"
    }
    #expect(
      titles == [
        "1/8 building master calibration frames", "2/8 grading + stacking TESTFIELD L",
        "3/8 grading + stacking TESTFIELD R", "4/8 grading + stacking TESTFIELD G",
        "5/8 grading + stacking TESTFIELD B", "6/8 aligning channels",
        "7/8 combining channels (Siril)", "8/8 writing the linear bundle",
      ])
    let previews = events.compactMap { event -> String? in
      if case .preview(let preview) = event { return preview.stage }
      return nil
    }
    #expect(previews == ["master_L", "master_R", "master_G", "master_B", "combined"])
    guard case .finished(let result) = try #require(events.last) else {
      Issue.record("the last event is not .finished")
      return
    }
    #expect(
      result.bundle?.layers.map(\.file) == [
        "trim_L.fits", "trim_R.fits", "trim_G.fits", "trim_B.fits",
      ])
    #expect(result.crop?.rect == EdgeRect(x0: 8, y0: 0, x1: 256, y1: 250))
    try await Self.cancelMidRun()
  }

  /// Cancelled while G stacks (the run's task cancelled from inside Siril, as a consumer's
  /// cancellation reaches it): L and R masters stay, G's never appears, no bundle is written.
  static func cancelMidRun() async throws {
    let request = try Self.request("R2")
    let siril = PipelineSiril(onRun: { script in
      if script.contains("-out=") && script.contains("master_G") {
        withUnsafeCurrentTask { $0?.cancel() }
      }
    })
    let (events, error) = await Self.collect(Preprocessor(tools: Self.tools(siril)).run(request))
    #expect(error is CancellationError)
    #expect(!events.contains(where: Self.isFinished))
    let out = request.output
    #expect(
      FileManager.default.fileExists(atPath: out.appendingPathComponent("master_R.fits").path))
    #expect(
      !FileManager.default.fileExists(atPath: out.appendingPathComponent("master_G.fits").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: out.appendingPathComponent(BundleWriter.fileName).path))
  }

  @Test(
    "a second run on the same output is refused; multi-night and mixed captures too",
    .scratchDirectory)
  func testRefusals() async throws {
    let request = try Self.request()
    // Another run holds the folder: this one is refused before anything runs.
    try TargetLock.acquire(request.output)
    let siril = PipelineSiril()
    let (_, busy) = await Self.collect(Preprocessor(tools: Self.tools(siril)).run(request))
    #expect(busy.map { String(describing: $0) }?.contains("targetBusy") == true)
    #expect(siril.calls.isEmpty)
    TargetLock.release(request.output)
    let (_, free) = await Self.collect(Preprocessor(tools: Self.tools(siril)).run(request))
    #expect(free == nil)

    var twoNights = request.inventory
    let light = try #require(twoNights.sets.first { $0.key.type == .light })
    var other = light
    other.key.session = "another night"
    twoNights.sets.append(other)
    #expect(throws: PreprocessError.multiNight([light.key.filter])) {
      _ = try Preprocessor.lightSets(twoNights)
    }
    twoNights.colorModel = .mixed
    #expect(throws: PreprocessError.mixedColorModel) { _ = try Preprocessor.lightSets(twoNights) }
  }
}
