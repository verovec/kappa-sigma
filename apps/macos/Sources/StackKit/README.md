# StackKit

Preprocessing, ported from the legacy Go engine (`../stacking-astro`, read-only): inspect, calibration
library, Siril driver, grading, multi-night, bundle; GraXpert and StarNet drivers (design §4.1, §4.3).

**State:** empty module (card 0040). Card 0044 brings the oracle loader and the StackKit seam.

**How to extend:** a port is pinned by a recorded oracle (scripts, selections, checksums); Siril does
the pixel math, so the same script and frame selection give a byte-identical master. Host tools run
through swift-subprocess; a missing tool is a typed error, never a fallback (R2). Allowed
dependencies: `ImageKit`, `ProjectKit` (`Tests/TestSupport/BoundaryRules.swift`).
