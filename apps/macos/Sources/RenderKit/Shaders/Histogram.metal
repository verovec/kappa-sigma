// Histogram: 256 bins per channel of the values clamped to [0, 1], sampled every `stride`
// pixels (quarter resolution at stride 2) — the linear values, or the displayed ones through the
// STF (STF.h) when `stfEnabled` (card 0085). Atomics are fine here: counts are exact integers and
// this kernel is not oracle-pinned to a summation order.
#include <metal_stdlib>
#include "ShaderTypes.h"
#include "STF.h"
using namespace metal;

kernel void histogram(texture2d<float, access::read> r [[texture(0)]],
                      texture2d<float, access::read> g [[texture(1)]],
                      texture2d<float, access::read> b [[texture(2)]],
                      device atomic_uint *bins [[buffer(0)]],
                      constant HistogramUniforms &u [[buffer(1)]],
                      uint2 gid [[thread_position_in_grid]]) {
  uint2 offset = gid * u.stride;
  if (offset.x >= u.width || offset.y >= u.height) { return; }
  uint2 pixel = uint2(u.originX, u.originY) + offset;
  float values[3] = {r.read(pixel).r, 0.0f, 0.0f};
  if (u.channels >= 3) {
    values[1] = g.read(pixel).r;
    values[2] = b.read(pixel).r;
  }
  for (uint c = 0; c < u.channels; ++c) {
    if (!isfinite(values[c])) { continue; }  // NaN/Inf blanks are not data
    float value = u.stfEnabled != 0 ? stf(values[c], u.shadows[c], u.midtone[c], u.highlights[c])
                                    : values[c];
    uint bin = uint(clamp(value, 0.0f, 1.0f) * 255.0f + 0.5f);
    atomic_fetch_add_explicit(&bins[c * 256 + min(bin, 255u)], 1u, memory_order_relaxed);
  }
}
