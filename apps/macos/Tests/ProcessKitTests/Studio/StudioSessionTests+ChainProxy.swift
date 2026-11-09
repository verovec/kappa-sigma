import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0189: while a value is dragged the chain renders on a proxy — the input reduced by an
/// integer factor, every `.px` value scaled with it — and comes back at the full size, said
/// reduced; at factor 1 there is no proxy and the full render is the frame.
@Suite(
  "StudioSession — the chain preview on a proxy while dragging",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct StudioSessionChainProxyTests {
  typealias Chain = StudioSessionChainTests

  /// A 64 × 32 colour ramp, smooth enough for a reduced render to come back close.
  static func ramp(_ offset: Float = 0) -> AstroImage {
    AstroImage(
      width: 64, height: 32,
      planes: (0..<3).map { plane in
        (0..<(64 * 32)).map { index in
          Float(index % 64) / 128 + Float(index / 64) / 256 + Float(plane) / 32 + offset
        }
      },
      metadata: ImageMetadata(rowOrder: .topDown))
  }

  /// A session over the 64 × 32 ramp whose proxy is a half (`proxyMaxSide` 32).
  static func session(_ name: String) throws -> StudioSession {
    let rgb = ramp(0.05)
    let stats = StudioSession.stats(of: rgb)
    let bundle = PipelineBundle(stats: stats, layers: ["RGB": rgb], layerStats: ["RGB": stats])
    let history = try History(
      directory: try ScratchDirectory.url.appendingPathComponent(name), original: ramp())
    let session = try StudioSession(
      history: history, bundle: bundle, registry: try Chain.registry(),
      device: try #require(MTLCreateSystemDefaultDevice()))
    session.proxyMaxSide = 32
    return session
  }

  static func meanAbsoluteDifference(_ one: AstroImage, _ two: AstroImage) -> Double {
    var sum = 0.0
    var count = 0
    for (first, second) in zip(one.planes, two.planes) {
      for (x, y) in zip(first, second) where x.isFinite && y.isFinite {
        sum += abs(Double(x) - Double(y))
        count += 1
      }
    }
    return count > 0 ? sum / Double(count) : .infinity
  }

  @Test("testPreviewChain_ProxyIsFullSizeAndReduced", .scratchDirectory)
  func testPreviewChain_ProxyIsFullSizeAndReduced() async throws {
    let session = try Self.session("applied")
    try Chain.applying(
      [try Chain.gain(1.5), try Chain.gain(0.8), try Chain.gain(1.2)], on: session)

    let proxy = try await session.previewChain(
      from: 0, params: try Chain.gain(0.7).params, level: .proxy)

    #expect(proxy.image.width == 64 && proxy.image.height == 32, "back at the full size")
    #expect(proxy.reduced, "said reduced")
    #expect(proxy.stoppedBefore == nil)
  }

  @Test("testPreviewChain_ProxyCloseToFull", .scratchDirectory)
  func testPreviewChain_ProxyCloseToFull() async throws {
    let session = try Self.session("applied")
    try Chain.applying([try Chain.gain(1.5), try Chain.gain(0.8)], on: session)
    let params = try Chain.gain(0.7).params

    let full = try await session.previewChain(from: 0, params: params, level: .full)
    let proxy = try await session.previewChain(from: 0, params: params, level: .proxy)

    #expect(!full.reduced)
    let difference = Self.meanAbsoluteDifference(full.image, proxy.image)
    #expect(difference <= 1.0 / 255, "mean |Δ| = \(difference)")
  }

  @Test("testPreviewChain_ProxyFactorOneIsFull", .scratchDirectory)
  func testPreviewChain_ProxyFactorOneIsFull() async throws {
    let session = try Chain.session("applied")  // 4 × 2: fits under any proxy side
    try Chain.applying([try Chain.gain(1.5), try Chain.gain(0.8)], on: session)
    let params = try Chain.gain(0.7).params

    let full = try await session.previewChain(from: 0, params: params, level: .full)
    let proxy = try await session.previewChain(from: 0, params: params, level: .proxy)

    #expect(!proxy.reduced, "no proxy to render on")
    #expect(Chain.same(full.image, proxy.image), "the full render, bit for bit")
  }

  /// A crop in the chain: the proxy comes back at the size the full chain ends on.
  @Test("testPreviewChain_ProxySizesAGeometricChain", .scratchDirectory)
  func testPreviewChain_ProxySizesAGeometricChain() async throws {
    let session = try Self.session("applied")
    try Chain.applying([try Chain.gain(1.5), try Chain.crop(), Chain.combination], on: session)
    let params = try Chain.gain(0.5).params

    let full = try await session.previewChain(from: 0, params: params, level: .full)
    let proxy = try await session.previewChain(from: 0, params: params, level: .proxy)

    #expect(full.image.width == 63, "the crop took one column")
    #expect(proxy.image.width == full.image.width && proxy.image.height == full.image.height)
    #expect(proxy.reduced)
  }
}
