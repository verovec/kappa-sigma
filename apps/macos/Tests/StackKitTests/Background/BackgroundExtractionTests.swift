import Foundation
import ImageKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// The engine behind the Studio's background extraction (card 0072): each engine returns the
/// corrected image and its model, a repeated request comes from the cache, a missing GraXpert is
/// an error that leaves the Siril engines untouched (never a fallback, R2).
@Suite("BackgroundExtraction: engines, cache, missing GraXpert", .serialized)
struct BackgroundExtractionTests {
  static let engines: [BackgroundEngine] = [
    .graxpert(smoothing: 0.5), .sirilRBF(smooth: 0.5, samples: 30, tolerance: 1.5, dither: true),
    .sirilPolynomial(degree: 2),
  ]

  /// A 4 × 3 RGB ramp, bottom-up like a Siril master.
  static func image() -> AstroImage {
    let planes = (0..<3).map { channel in (0..<12).map { Float($0 + channel * 12) / 40 + 0.1 } }
    return AstroImage(
      width: 4, height: 3, planes: planes, metadata: ImageMetadata(rowOrder: .bottomUp))
  }

  @Test(
    "each engine yields corrected + model of the input size; a repeated request makes no tool call",
    .scratchDirectory, arguments: engines)
  func testEnginesAndCache(engine: BackgroundEngine) async throws {
    let scratch = try ScratchDirectory.url
    let tools = FakeBackgroundTools()
    let graxpert = try tools.graxpert(in: scratch)
    let extraction = BackgroundExtraction(graxpert: { graxpert }, siril: tools.siril)
    let progress = Mutex<[ToolProgress]>([])

    let first = try await extraction.run(
      image: Self.image(), engine: engine, correction: .subtract, scratch: scratch
    ) { event in progress.withLock { $0.append(event) } }
    #expect(first.corrected.width == 4 && first.corrected.height == 3)
    #expect(first.corrected.planes.count == 3 && first.model.planes.count == 3)
    #expect(first.model.width == 4 && first.model.height == 3)
    #expect(first.corrected.metadata.rowOrder == .bottomUp && !first.reused)
    // The fakes return the input untouched: the subtraction model is zero everywhere.
    #expect(first.model.planes.joined().allSatisfy { $0 == 0 })
    #expect(first.corrected.planes == Self.image().planes)
    #expect(!progress.withLock { $0 }.isEmpty)
    let calls = (tools.graxpertCalls.withLock { $0 }, tools.sirilCalls.withLock { $0 })
    #expect(calls == (engine.usesGraXpert ? 1 : 0, engine.usesGraXpert ? 0 : 1))

    let again = try await extraction.run(
      image: Self.image(), engine: engine, correction: .subtract, scratch: scratch
    ) { _ in }
    #expect(again.reused && again.corrected.planes == first.corrected.planes)
    #expect(again.model.planes == first.model.planes)
    #expect((tools.graxpertCalls.withLock { $0 }, tools.sirilCalls.withLock { $0 }) == calls)

    // A different correction is another request (GraXpert only: Siril's subsky subtracts).
    guard engine.usesGraXpert else { return }
    let divided = try await extraction.run(
      image: Self.image(), engine: engine, correction: .divide, scratch: scratch
    ) { _ in }
    #expect(!divided.reused && divided.model.planes.joined().allSatisfy { $0 == 1 })
    #expect(tools.graxpertCalls.withLock { $0 } == 2)
  }

  @Test(
    "a Siril engine only subtracts: asking it to divide is refused, not reinterpreted",
    .scratchDirectory)
  func testSirilEnginesRefuseDivide() async throws {
    let tools = FakeBackgroundTools()
    let extraction = BackgroundExtraction(
      graxpert: { throw GraXpertError.missing(path: "x") }, siril: tools.siril)
    await #expect(
      throws: BackgroundExtractionError.unsupportedCorrection(
        engine: .sirilPolynomial(degree: 1), correction: .divide)
    ) {
      try await extraction.run(
        image: Self.image(), engine: .sirilPolynomial(degree: 1), correction: .divide,
        scratch: try ScratchDirectory.url
      ) { _ in }
    }
    #expect(tools.sirilCalls.withLock { $0 } == 0)
  }

  @Test(
    "GraXpert absent → GraXpertError.missing; the Siril engines are untouched", .scratchDirectory)
  func testMissingGraXpertLeavesSirilEngines() async throws {
    let scratch = try ScratchDirectory.url
    let tools = FakeBackgroundTools()
    let extraction = BackgroundExtraction.located(
      by: HostTools { _ in .missing(path: "/Applications/GraXpert.app") }, siril: tools.siril)
    await #expect(throws: GraXpertError.missing(path: "/Applications/GraXpert.app")) {
      try await extraction.run(
        image: Self.image(), engine: .graxpert(smoothing: 0.5), correction: .subtract,
        scratch: scratch
      ) { _ in }
    }
    #expect(tools.sirilCalls.withLock { $0 } == 0)
    let result = try await extraction.run(
      image: Self.image(), engine: .sirilPolynomial(degree: 1), correction: .subtract,
      scratch: scratch
    ) { _ in }
    #expect(result.corrected.width == 4 && tools.sirilCalls.withLock { $0 } == 1)
  }

  @Test(
    "a tool output without a ROWORDER card is read in the input's order; only the pair stays",
    .scratchDirectory)
  func testOutputWithoutRowOrderCard() async throws {
    let scratch = try ScratchDirectory.url
    // GraXpert played by a copy of the input whose ROWORDER card is blanked.
    let stripping = GraXpertRunner { input, output, _, _ in
      try FileManager.default.copyItem(at: input, to: output)
      try FITSFile.stripKeyword("ROWORDER", at: output)
      return ""
    }
    let extraction = BackgroundExtraction(
      graxpert: { stripping }, siril: SirilRunner { _, _, _ in "" })
    let topDown = AstroImage(
      width: 4, height: 3, planes: Self.image().planes, metadata: ImageMetadata(rowOrder: .topDown))
    let result = try await extraction.run(
      image: topDown, engine: .graxpert(smoothing: 0.5), correction: .subtract, scratch: scratch
    ) { _ in }
    #expect(result.corrected.planes == Self.image().planes)
    #expect(result.corrected.metadata.rowOrder == .topDown)
    #expect(result.model.planes.joined().allSatisfy { $0 == 0 })
    let background = scratch.appendingPathComponent("background")
    let keys = try FileManager.default.contentsOfDirectory(atPath: background.path)
    let kept = try FileManager.default.contentsOfDirectory(
      atPath: background.appendingPathComponent(try #require(keys.first)).path)
    #expect(keys.count == 1 && kept.sorted() == ["corrected.fits", "model.fits"])
  }

  @Test(
    "a value outside the engine's range is refused before any tool runs",
    arguments: [
      BackgroundEngine.graxpert(smoothing: 1.5), .sirilPolynomial(degree: 0),
      .sirilPolynomial(degree: 5),
      .sirilRBF(smooth: -0.1, samples: 30, tolerance: 1.5, dither: true),
      .sirilRBF(smooth: 0.5, samples: 0, tolerance: 1.5, dither: false),
    ])
  func testOutOfRange(engine: BackgroundEngine) {
    #expect(throws: BackgroundExtractionError.self) { try engine.validate() }
  }
}
