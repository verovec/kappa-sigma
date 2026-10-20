# ImageKit

Images as data: FITS float32 I/O, planar `[Float32]` planes, mip pyramid, tiles (design §4.5b, §4.6).
No UI, no Metal: RenderKit uploads what ImageKit produces.

**State:** empty module (card 0040). Card 0041 brings the FITS reader/writer and the pyramid.

**How to extend:** heavy CPU work is `nonisolated` + `@concurrent` and goes through Accelerate
(`conventions/swift-conventions.md`); buffers are non-Sendable `final class` wrappers passed with
`sending`. Allowed dependencies: none (`Tests/TestSupport/BoundaryRules.swift`).
