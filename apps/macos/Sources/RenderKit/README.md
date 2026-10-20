# RenderKit

The Metal viewer and shaders: zoom/pan, 1:1 region, display stretch, histogram, and the kernels the
processes run (design §4.1, §4.6).

**State:** empty module (card 0040). Card 0042 brings the viewer.

**How to extend:** Metal 3, fast-math off for every oracle-pinned kernel, runtime
`makeLibrary(source:)` until E19 (no Xcode needed); logic stays in plain Swift so it tests without a
GPU. RenderKit is one of the two modules allowed to import SwiftUI/AppKit (its views). Allowed
dependencies: `ImageKit` (`Tests/TestSupport/BoundaryRules.swift`).
