import AppKit
import AstroStackApp
import Foundation
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The Stacking and Studio panes over a run in each phase, in fr and en; the channel lines a
/// finished run shows.
@MainActor
@Suite("Run panel — every run phase lays out; the Studio shows the stack")
struct RunPanelTests {
  enum Phase: String, Sendable, CaseIterable {
    case running, finished, failed, cancelled
  }

  struct Variant: Sendable, CustomTestStringConvertible {
    let phase: Phase
    let language: String
    var testDescription: String { "\(phase)-\(language)" }
  }

  nonisolated static let variants = Phase.allCases.flatMap { phase in
    ["en", "fr"].map { Variant(phase: phase, language: $0) }
  }

  nonisolated static func outcome(_ filter: String, frames: Int) -> ChannelOutcome {
    let key = SetKey(
      type: .light, object: "M31", filter: filter, exposureMs: 300_000, gain: 100, offset: 50,
      tempBucketC: -10, bin: 1, session: "2026-09-22")
    var outcome = ChannelOutcome(
      FrameSet(key: key, frames: [], indices: []), filter: filter,
      selection: CalibrationSelection())
    outcome.inputFrames = frames
    return outcome
  }

  nonisolated static var channels: [ChannelOutcome] {
    var rgb = outcome("RGB", frames: 36)
    rgb.stackedFrames = 34
    var mask = TrailMaskSummary()
    mask.frames = 34
    mask.framesWithTrails = 3
    mask.segments = 5
    rgb.trailMask = mask
    var ha = outcome("Ha", frames: 2)
    ha.error = "below Siril's two-frame stack minimum"
    return [rgb, ha]
  }

  /// A run that stops in `phase`; a running one stays open until the test cancels it.
  nonisolated static func run(
    _ phase: Phase, open: Recorded<AsyncThrowingStream<PreprocessEvent, any Error>.Continuation>
  )
    -> RunServices.Run
  {
    { request in
      let begin = PreprocessEvent.progress(
        .init(
          step: 1, steps: 5, title: "building master calibration frames", percent: nil, line: ""))
      let line = PreprocessEvent.progress(
        .init(
          step: 1, steps: 5, title: "building master calibration frames", percent: 40,
          line: "⚠ flat master saturated in a corner"))
      let preview = PreprocessEvent.preview(
        .init(stage: "master_RGB", pngPath: request.output.path + "/master_RGB_preview.png"))
      let (stream, continuation) = AsyncThrowingStream.makeStream(of: PreprocessEvent.self)
      for event in [begin, line, preview] { continuation.yield(event) }
      switch phase {
      case .running:
        open.append(continuation)
      case .finished:
        do {
          continuation.yield(.finished(try finished(request)))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      case .failed:
        continuation.finish(throwing: PreprocessError.noChannels(["RGB: no frame survived"]))
      case .cancelled:
        continuation.finish(throwing: CancellationError())
      }
      return stream
    }
  }

  /// A finished run's result: a two-layer bundle written into its output, channels, notes and
  /// warnings.
  nonisolated static func finished(_ request: PreprocessRequest) throws -> PreprocessResult {
    try FileManager.default.createDirectory(at: request.output, withIntermediateDirectories: true)
    var result = PreprocessResult(runID: request.runID)
    result.bundle = try ProjectTests.writeBundle(in: request.output, runID: request.runID)
    result.channels = channels
    result.notes = ["dual-band split into syn_Ha and syn_OIII (continuum k 0.115)"]
    result.warnings = ["no plate solve: the parity check was skipped"]
    return result
  }

  @Test(
    "the Stacking pane lays out a run in every phase, in fr and en", .scratchDirectory,
    arguments: variants)
  func testRunPhasesLayOut(_ variant: Variant) async throws {
    let open = Recorded<AsyncThrowingStream<PreprocessEvent, any Error>.Continuation>()
    let fixture = try ProjectTests.fixture(run: Self.run(variant.phase, open: open))
    defer { try? fixture.project.close() }
    let window = fixture.window
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.startRun()
    if variant.phase != .running { await window.run?.settled() }
    window.select(.stacking)

    let host = ImportSheetTests.host(
      ProjectWindowView(model: window).environment(\.locale, Locale(identifier: variant.language))
        .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 640 && host.fittingSize.height >= 400)
    if variant.language == "en" { try Self.attach(host, "run-\(variant.phase).png") }

    if variant.phase == .running {
      #expect(window.run?.isRunning == true)
      window.cancelRun()
      await window.run?.settled()
      #expect(window.run?.phase == .cancelled)
      open.all.forEach { $0.finish() }
    }
  }

  @Test(
    "after a run the Studio lists the stack's layers", .scratchDirectory, arguments: ["en", "fr"])
  func testStudioShowsStack(_ language: String) async throws {
    let open = Recorded<AsyncThrowingStream<PreprocessEvent, any Error>.Continuation>()
    let fixture = try ProjectTests.fixture(run: Self.run(.finished, open: open))
    defer { try? fixture.project.close() }
    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    fixture.window.startRun()
    await fixture.window.run?.settled()
    #expect(fixture.window.selection == .studio)

    let host = ImportSheetTests.host(
      ProjectWindowView(model: fixture.window).environment(\.locale, Locale(identifier: language))
        .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 640)
    if language == "en" { try Self.attach(host, "studio-stack.png") }
  }

  @Test(
    "a finished run words each channel and its trail mask",
    arguments: [
      (
        "en",
        [
          "RGB: 34 of 36 frames stacked", "Ha: not stacked — below Siril's two-frame stack minimum",
          "RGB trail mask: 5 trails on 3 of 34 frames",
        ]
      ),
      (
        "fr",
        [
          "RGB : 34 sur 36 poses empilées",
          "Ha : non empilé — below Siril's two-frame stack minimum",
          "RGB, masque de traînées : 5 traînées sur 3 des 34 poses",
        ]
      ),
    ])
  func testChannelLines(_ language: String, _ expected: [String]) {
    var result = PreprocessResult(runID: "R")
    result.channels = Self.channels
    let locale = Locale(identifier: language)
    let lines =
      RunSummary.channels(result, locale: locale) + RunSummary.trailMasks(result, locale: locale)
    #expect(lines.map { String(localized: $0) } == expected)
  }

  static func attach(_ host: NSView, _ name: String) throws {
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    Attachment.record(png, named: name)
  }
}
