// Masks (card 0054): built and blended in the kit, so no process implements masking itself.
// Pinned against CPU oracles in MaskTests; fast-math off.
#include <metal_stdlib>
using namespace metal;

static float luma(texture2d<float, access::read> r, texture2d<float, access::read> g,
                  texture2d<float, access::read> b, uint2 gid, uint channels) {
  float red = r.read(gid).r;
  if (channels < 3) { return red; }
  return 0.2126f * red + 0.7152f * g.read(gid).r + 0.0722f * b.read(gid).r;
}

// 1 inside [low, high], linear ramps of width `soft` outside (a hard edge when soft = 0).
static float range(float y, float low, float high, float soft) {
  if (soft <= 0.0f) { return (y >= low && y <= high) ? 1.0f : 0.0f; }
  float rise = clamp((y - (low - soft)) / soft, 0.0f, 1.0f);
  float fall = clamp(((high + soft) - y) / soft, 0.0f, 1.0f);
  return rise * fall;
}

// p[0] low · p[1] high · p[2] softness · p[3] 1 to invert · p[4] channels
kernel void maskLuminosityRange(texture2d<float, access::read> r [[texture(0)]],
                                texture2d<float, access::read> g [[texture(1)]],
                                texture2d<float, access::read> b [[texture(2)]],
                                texture2d<float, access::write> mask [[texture(3)]],
                                constant float *p [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= mask.get_width() || gid.y >= mask.get_height()) { return; }
  float m = range(luma(r, g, b, gid, uint(p[4])), p[0], p[1], p[2]);
  mask.write(float4(p[3] != 0.0f ? 1.0f - m : m), gid);
}

// Stars proxy: luma above its local mean (box of radius p[1]): 0 below p[0], ramping to 1 at
// 2·p[0] — flat sky (and its rounding noise) stays at 0.
// p[0] threshold · p[1] radius · p[2] 1 to invert · p[3] channels
kernel void maskStars(texture2d<float, access::read> r [[texture(0)]],
                      texture2d<float, access::read> g [[texture(1)]],
                      texture2d<float, access::read> b [[texture(2)]],
                      texture2d<float, access::write> mask [[texture(3)]],
                      constant float *p [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= mask.get_width() || gid.y >= mask.get_height()) { return; }
  int radius = int(p[1]);
  int2 size = int2(mask.get_width(), mask.get_height());
  float sum = 0.0f;
  for (int dy = -radius; dy <= radius; ++dy) {
    for (int dx = -radius; dx <= radius; ++dx) {
      uint2 at = uint2(clamp(int2(gid) + int2(dx, dy), int2(0), size - 1));
      sum += luma(r, g, b, at, uint(p[3]));
    }
  }
  float mean = sum / float((2 * radius + 1) * (2 * radius + 1));
  float m = clamp((luma(r, g, b, gid, uint(p[3])) - mean - p[0]) / p[0], 0.0f, 1.0f);
  mask.write(float4(p[2] != 0.0f ? 1.0f - m : m), gid);
}

// Feather: one pass of a box blur of radius `radius` along x (horizontal) or y, edge-clamped.
kernel void maskBoxBlur(texture2d<float, access::read> src [[texture(0)]],
                        texture2d<float, access::write> dst [[texture(1)]],
                        constant int2 &radiusAxis [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
  int radius = radiusAxis.x;
  int2 step = radiusAxis.y == 0 ? int2(1, 0) : int2(0, 1);
  int2 size = int2(src.get_width(), src.get_height());
  float sum = 0.0f;
  for (int k = -radius; k <= radius; ++k) {
    sum += src.read(uint2(clamp(int2(gid) + step * k, int2(0), size - 1))).r;
  }
  dst.write(float4(sum / float(2 * radius + 1)), gid);
}

// out = m · processed + (1 − m) · input, per plane (the kit's generic mask).
kernel void maskBlend(texture2d<float, access::read> input [[texture(0)]],
                      texture2d<float, access::read> processed [[texture(1)]],
                      texture2d<float, access::read> mask [[texture(2)]],
                      texture2d<float, access::write> out [[texture(3)]],
                      uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
  float m = mask.read(gid).r;
  float a = input.read(gid).r;
  float b = processed.read(gid).r;
  out.write(float4(m == 1.0f ? b : (m == 0.0f ? a : m * b + (1.0f - m) * a)), gid);
}
