import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

extension GeometryProcessTests {
  static func image(_ width: Int, _ height: Int, planes: Int, seed: Float) -> AstroImage {
    AstroImage(
      width: width, height: height,
      planes: (0..<planes).map { plane in
        (0..<width * height).map { seed + Float(plane) * 100 + Float($0) }
      },
      metadata: ImageMetadata(rowOrder: .bottomUp))
  }

  /// Card 0090: an applied geometry step moves the image and every layer the next steps read —
  /// the bundle's (`RGB`, `Ha`, `OIII`) as its bundle layers, an earlier step's `starless` as
  /// its output of that role — to one size, and their statistics are measured again (Hα keeps
  /// its recorded continuum fit).
  @Test("testLayersFollow", .scratchDirectory)
  func testLayersFollow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (width, height) = (6, 4)
    let bundle = PipelineBundle(
      stats: LayerStats(channels: []),
      layers: [
        "RGB": Self.image(width, height, planes: 3, seed: 0),
        "Ha": Self.image(width, height, planes: 1, seed: 1000),
        "OIII": Self.image(width, height, planes: 1, seed: 2000),
      ],
      layerStats: ["Ha": LayerStats(channels: [], continuumK: 0.42, continuumReference: "RGB.r")])
    let history = try History(
      directory: ScratchDirectory.url.appendingPathComponent("history"),
      original: Self.image(width, height, planes: 3, seed: 0))
    let session = try StudioSession(
      history: history, bundle: bundle, registry: ProcessRegistry([GeometryProcess.self]),
      device: device)
    try session.apply(
      "stars", params: ParamSet(schema: GeometryProcess.schema), result: history.current,
      outputs: [.starless: Self.image(width, height, planes: 3, seed: 3000)])

    try session.apply("geometry", params: Self.params(Self.layerValues))

    let step = try #require(history.steps.last)
    #expect(step.bundleLayers.keys.sorted() == ["Ha", "OIII", "RGB"])
    #expect(step.outputs.keys.map(\.rawValue) == ["starless"])
    let head = history.current
    #expect(head.width == 3 && head.height == 5)
    let moved = try history.bundleLayers().merging(
      history.layers().map { ($0.key.rawValue, $0.value) }
    ) { $1 }
    for (id, layer) in moved {
      #expect(layer.width == head.width && layer.height == head.height, "\(id)")
      let source =
        id == "starless"
        ? Self.image(width, height, planes: 3, seed: 3000) : try #require(bundle.layers[id])
      // Bottom-up rows: the display oracle runs on the reversed rows.
      for (plane, pixels) in source.planes.enumerated() {
        let rows = (0..<height).map { Array(pixels[$0 * width..<($0 + 1) * width]) }.reversed()
        let want = Self.expected(Array(rows), Self.layerValues)
        #expect(layer.planes[plane] == Array(want.reversed().joined()), "\(id) plane \(plane)")
      }
    }
    let stats = try session.layerStats()
    #expect(stats["Ha"]?.channels == LayerStats.measured(try #require(moved["Ha"])).channels)
    #expect(stats["Ha"]?.continuumK == 0.42 && stats["Ha"]?.continuumReference == "RGB.r")
    #expect(stats["starless"] == LayerStats.measured(try #require(moved["starless"])))
  }

  static let layerValues: [String: ParamValue] = [
    "cropLeft": .number(1), "cropTop": .number(1), "rotation": .choice("90"),
  ]
}
