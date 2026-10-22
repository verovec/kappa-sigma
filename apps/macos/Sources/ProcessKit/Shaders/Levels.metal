// Histogram transformation (card 0089): per channel its own triple when unlinked, then the RGB/K
// triple, then the output range. Each triple is `stf` of the shared STF.h — the viewer's display
// stretch, one formula for the display, the stretch and this process. An inactive triple (the
// identity) is skipped, so the defaults return the input bit for bit. Fast-math off.
#include <metal_stdlib>
#include "STF.h"
using namespace metal;

// p[0] planes · p[1] unlinked · p[2 + 4t] active, c0, m, c1 of triple t (RGB/K, R, G, B)
// p[18] output active, p[19] low, p[20] high
static float triple(float x, constant float *t) {
  return t[0] != 0.0f ? stf(x, t[1], t[2], t[3]) : x;
}

kernel void levels(
  texture2d<float, access::read> in0 [[texture(0)]],
  texture2d<float, access::read> in1 [[texture(1)]],
  texture2d<float, access::read> in2 [[texture(2)]],
  texture2d<float, access::write> out0 [[texture(3)]],
  texture2d<float, access::write> out1 [[texture(4)]],
  texture2d<float, access::write> out2 [[texture(5)]],
  constant float *p [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= out0.get_width() || gid.y >= out0.get_height()) { return; }
  uint planes = uint(p[0]);
  float values[3] = { in0.read(gid).r, in1.read(gid).r, in2.read(gid).r };
  for (uint c = 0; c < planes; c++) {
    float v = values[c];
    if (p[1] != 0.0f) { v = triple(v, p + 6 + 4 * c); }
    v = triple(v, p + 2);
    if (p[18] != 0.0f) { v = fma(v, p[20] - p[19], p[19]); }
    values[c] = v;
  }
  out0.write(float4(values[0]), gid);
  if (planes == 3) {
    out1.write(float4(values[1]), gid);
    out2.write(float4(values[2]), gid);
  }
}
