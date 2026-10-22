import Foundation
import ImageKit
import Metal
import ProcessKit
import Synchronization
import TestSupport
import Testing

/// Background extraction as a Studio process (card 0092): a batch process whose result comes
/// from the engine the user chose (GraXpert, Siril RBF, Siril polynomial), applied to the layers
/// `applyTo` names, the model kept as a step output. The engine here is a fake: corrected =
/// image − 1, model = 1, recorded per call.
@Suite("Background extraction process — schema, targets, batch result")
struct BackgroundExtractionProcessTests {
  /// What the fake engine saw, in call order.
  final class Calls: Sendable {
    private let storage = Mutex<[Float]>([])
    var firstPixels: [Float] { storage.withLock { $0 } }
    func record(_ value: Float) { storage.withLock { $0.append(value) } }
  }

  static func image(_ value: Float, planes: Int = 1) -> AstroImage {
    AstroImage(
      width: 2, height: 2,
      planes: Array(repeating: [Float](repeating: value, count: 4), count: planes),
      metadata: ImageMetadata(rowOrder: .topDown))
  }

  static func fake(_ calls: Calls) -> BackgroundExtractionProcess.Extract {
    { image, _, progress in
      calls.record(image.planes[0][0])
      progress(1)
      let corrected = AstroImage(
        width: image.width, height: image.height, planes: image.planes.map { $0.map { $0 - 1 } },
        metadata: image.metadata)
      return (corrected, Self.image(1, planes: image.planes.count))
    }
  }

  static func params(_ values: [String: ParamValue]) throws -> ParamSet {
    var params = ParamSet(schema: BackgroundExtractionProcess.schema)
    for (id, value) in values { try params.set(id, value) }
    return params
  }

  @Test("registered as a linear batch process with the engine choice first")
  func testRegistered() throws {
    let registry = try ProcessRegistry.standard()
    #expect(registry.type(id: "background-extraction") == BackgroundExtractionProcess.self)
    #expect(BackgroundExtractionProcess.hostTool && BackgroundExtractionProcess.stage == .linear)
    let defaults = ParamSet(schema: BackgroundExtractionProcess.schema)
    #expect(BackgroundExtractionProcess.schema.specs.first?.id == "engine")
    #expect(defaults["engine"] == .choice("graxpert") && defaults["applyTo"] == .choice("rgb"))
    #expect(defaults["correction"] == .choice("subtract"))
  }

  @Test(
    "the chosen engine promotes its own values out of the disclosure",
    arguments: zip(
      ["graxpert", "siril-rbf", "siril-polynomial"],
      [["smoothing"], ["rbfSmooth", "samples", "tolerance", "dither"], ["degree"]]))
  func testPromotedByEngine(engine: String, promoted: Set<String>) throws {
    let params = try Self.params(["engine": .choice(engine)])
    #expect(BackgroundExtractionProcess.promoted(params) == promoted)
  }

  /// One row: what `applyTo` says, the bundle's layer ids, what is rewritten.
  struct TargetCase: Sendable, CustomTestStringConvertible {
    let applyTo: String
    let ids: [String]
    let head: Bool
    let layers: [String]
    var testDescription: String { "\(applyTo) over \(ids)" }
  }

  @Test(
    "testTargets",
    arguments: [
      TargetCase(applyTo: "rgb", ids: ["RGB", "Ha", "OIII"], head: true, layers: []),
      TargetCase(
        applyTo: "lines", ids: ["RGB", "Ha", "OIII"], head: false, layers: ["Ha", "OIII"]),
      TargetCase(applyTo: "lines", ids: ["RGB"], head: false, layers: []),
      TargetCase(
        applyTo: "all", ids: ["RGB", "L", "SII", "Ha"], head: true,
        layers: ["Ha", "L", "RGB", "SII"]),
    ])
  func testTargets(row: TargetCase) throws {
    let params = try Self.params(["applyTo": .choice(row.applyTo)])
    let targets = BackgroundExtractionProcess.targets(params, layerIDs: row.ids)
    #expect(targets == .init(head: row.head, layers: row.layers))
  }

  @Test("a scope with nothing to correct is refused with the reason, before any engine runs")
  func testNothingToCorrect() async throws {
    let calls = Calls()
    let batch = BackgroundExtractionProcess.batch(Self.fake(calls))
    let params = try Self.params(["applyTo": .choice("lines")])
    await #expect(throws: ProcessError.missingLayer("an emission line layer (Ha, OIII, SII)")) {
      _ = try await batch.step(
        .init(image: Self.image(5, planes: 3), layers: ["RGB": Self.image(4, planes: 3)]), params
      ) { _ in }
    }
    #expect(calls.firstPixels.isEmpty)
  }

  @Test("the step: corrected head and lines, the model of the first target, progress in order")
  func testBatchStep() async throws {
    let calls = Calls()
    let batch = BackgroundExtractionProcess.batch(Self.fake(calls))
    let params = try Self.params(["applyTo": .choice("all")])
    let progress = Mutex<[Double]>([])
    let input = PipelineRunner.BatchInput(
      image: Self.image(5, planes: 3),
      layers: ["RGB": Self.image(4, planes: 3), "Ha": Self.image(3)])
    let output = try await batch.step(input, params) { value in
      progress.withLock { $0.append(value) }
    }
    #expect(calls.firstPixels == [5, 3, 4], "head first, then the layers by id")
    #expect(output.result.planes[0][0] == 4)
    #expect(output.replaced.mapValues { $0.planes[0][0] } == ["Ha": 2, "RGB": 3])
    #expect(output.outputs.keys.map(\.self) == [.backgroundModel])
    #expect(output.outputs[.backgroundModel]?.planes.count == 3, "the head's model")
    #expect(progress.withLock { $0 } == [1.0 / 3, 2.0 / 3, 1])
  }

  @Test("lines only: the head is kept as it is, the model is the first line's")
  func testLinesKeepHead() async throws {
    let batch = BackgroundExtractionProcess.batch(Self.fake(Calls()))
    let params = try Self.params(["applyTo": .choice("lines")])
    let input = PipelineRunner.BatchInput(
      image: Self.image(5, planes: 3),
      layers: ["RGB": Self.image(4, planes: 3), "OIII": Self.image(2), "Ha": Self.image(3)])
    let output = try await batch.step(input, params) { _ in }
    #expect(output.result.planes == input.image.planes)
    #expect(output.replaced.mapValues { $0.planes[0][0] } == ["Ha": 2, "OIII": 1])
    #expect(output.outputs[.backgroundModel]?.planes.count == 1)
  }
}

extension BackgroundExtractionProcessTests {
  @Test(
    "preview is the image; Apply and a pipeline without the tool are refused by name",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testNoGPURenderNoSubstitute() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let registry = try ProcessRegistry.standard()
    let original = Self.image(0.5, planes: 3)
    let history = try History(
      directory: ScratchDirectory.url.appendingPathComponent("h"), original: original)
    let bundle = PipelineBundle(
      stats: StudioSession.stats(of: original), layers: ["RGB": original])
    let session = try StudioSession(
      history: history, bundle: bundle, registry: registry, device: device)
    let defaults = ParamSet(schema: BackgroundExtractionProcess.schema)
    #expect(
      try session.render(BackgroundExtractionProcess.id, params: defaults).planes
        == original.planes)
    #expect(throws: StudioError.needsTool("background-extraction")) {
      try session.apply(BackgroundExtractionProcess.id, params: defaults)
    }
    let pipeline = Pipeline(
      name: "M31",
      steps: [
        PipelineStep(
          recipe: Recipe(
            processID: BackgroundExtractionProcess.id,
            params: ParamSet(schema: BackgroundExtractionProcess.schema)))
      ])
    let runner = try PipelineRunner(registry: registry, device: device)
    await #expect(throws: PipelineError.toolMissing("background-extraction")) {
      _ = try await runner.run(pipeline, on: history, bundle: bundle)
    }
    #expect(history.steps.isEmpty)
  }

  @Test(
    "a pipeline with the tool: one step, the model as an output, the rewritten layers in context",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testPipelineAppliesBatch() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let original = Self.image(5, planes: 3)
    let history = try History(
      directory: ScratchDirectory.url.appendingPathComponent("h"), original: original)
    let bundle = PipelineBundle(
      stats: StudioSession.stats(of: original), layers: ["RGB": original, "Ha": Self.image(3)])
    let registry = try ProcessRegistry.standard()
    let session = try StudioSession(
      history: history, bundle: bundle, registry: registry, device: device)
    let runner = try PipelineRunner(
      registry: registry, device: device,
      batch: [BackgroundExtractionProcess.id: BackgroundExtractionProcess.batch(Self.fake(Calls()))]
    )
    func step(_ applyTo: String) throws -> PipelineStep {
      PipelineStep(
        recipe: Recipe(
          processID: BackgroundExtractionProcess.id,
          params: try Self.params(["applyTo": .choice(applyTo)])))
    }
    _ = try await runner.run(Pipeline(name: "a", steps: [step("all")]), on: history, bundle: bundle)
    #expect(history.steps.map(\.processID) == ["background-extraction"])
    #expect(history.current.planes[0][0] == 4)
    #expect(session.layerIDs().contains("backgroundModel"))
    #expect(try history.context(over: bundle.layers)["Ha"]?.planes[0][0] == 2)
    // A second run reads the layers as the first one left them.
    _ = try await runner.run(
      Pipeline(name: "b", steps: [step("all"), step("lines")]), on: history, bundle: bundle,
      from: 1)
    #expect(try history.context(over: bundle.layers)["Ha"]?.planes[0][0] == 1)
  }
}
