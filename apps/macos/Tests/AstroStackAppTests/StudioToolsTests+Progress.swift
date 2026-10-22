import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import StackKit
import TestSupport
import Testing

extension StudioToolsTests {
  /// Siril's file side for `load X … save Y` (the image back untouched), each command printing
  /// « 50% »: what the tool's progress reads.
  static let halfwaySiril = SirilRunner { script, directory, onLine in
    var loaded: String?
    for command in script.commands {
      switch command {
      case .load(let name): loaded = name
      case .save(let name):
        if let loaded {
          try FileManager.default.copyItem(
            at: directory.appendingPathComponent("\(loaded).fits"),
            to: directory.appendingPathComponent("\(name).fits"))
        }
      default: break
      }
    }
    onLine(SirilLine(parsing: "log: subsky 50%"))
    return ""
  }

  /// Card 0092: the run over every target shows one bar — each target's « 50% » lands in its
  /// third of it — and leaves no work files behind.
  @Test("the progress of a run over three targets reads as one bar", .scratchDirectory)
  func testProgressSharedAcrossTargets() async throws {
    let scratch = try ScratchDirectory.url.appendingPathComponent("bge")
    let extraction = BackgroundExtraction(
      graxpert: { throw GraXpertError.missing(path: "/nowhere") }, siril: Self.halfwaySiril)
    let tool = BackgroundExtractionTool.tool(extraction: extraction, scratch: scratch)
    let seen = Recorded<Int>()
    let replaced = try await Self.runAllTargets(tool, seen: seen)
    #expect(seen.all == [16, 50, 83])
    #expect(replaced == ["Ha", "RGB", "backgroundModel"])
    let left = (try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []
    #expect(left.isEmpty, "work files removed: \(left)")
  }

  /// `tool` over a head and two bundle layers with the Siril polynomial on all of them: the
  /// layers it rewrote and the roles it wrote, sorted; its progress into `seen`.
  nonisolated static func runAllTargets(_ tool: StudioTool, seen: Recorded<Int>) async throws
    -> [String]
  {
    // Three different images: none is served from the extraction's cache.
    func image(_ planes: Int, _ level: Float) -> AstroImage {
      AstroImage(
        width: 2, height: 2,
        planes: Array(repeating: [0.1, 0.2, 0.3, 0.4].map { $0 + level }, count: planes),
        metadata: ImageMetadata(rowOrder: .topDown))
    }
    var params = ParamSet(schema: BackgroundExtractionProcess.schema)
    try params.set("engine", .choice("siril-polynomial"))
    try params.set("applyTo", .choice("all"))
    let output = try await tool.step(
      PipelineRunner.BatchInput(
        image: image(3, 0), layers: ["RGB": image(3, 0.1), "Ha": image(1, 0)]),
      params
    ) { progress in
      if let percent = progress.percent { seen.append(percent) }
    }
    return (Array(output.replaced.keys) + output.outputs.keys.map(\.rawValue)).sorted()
  }
}
