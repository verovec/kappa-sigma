// Two-scale HDR core compression (card 0052): the port of hdrcomp, pinned against HDROracle in
// HDRTests and against hdrcomp's recorded output on run #78 in HDRLiveTests. Fast-math off.
#include <metal_stdlib>
using namespace metal;

// L = mean(R, G, B), summed in float like hdrcomp; a mono image is its own luminance.
// p[0] channels
kernel void hdrLuminance(texture2d<float, access::read> r [[texture(0)]],
                         texture2d<float, access::read> g [[texture(1)]],
                         texture2d<float, access::read> b [[texture(2)]],
                         texture2d<float, access::write> lum [[texture(3)]],
                         constant float *p [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= lum.get_width() || gid.y >= lum.get_height()) { return; }
  float red = r.read(gid).r;
  lum.write(float4(p[0] < 3.0f ? red : (red + g.read(gid).r + b.read(gid).r) / 3.0f), gid);
}

// Above t1 the smooth part becomes t1 + s·asinh((smooth − t1) / s) — slope 1 at t1, so the curve
// is C1 — the detail L − smooth is put back, and every channel is scaled by L′ / L.
// p[0] channels · p[1] t1 (sky + knee) · p[2] softness s
kernel void hdrCompress(texture2d<float, access::read> r [[texture(0)]],
                        texture2d<float, access::read> g [[texture(1)]],
                        texture2d<float, access::read> b [[texture(2)]],
                        texture2d<float, access::read> lum [[texture(3)]],
                        texture2d<float, access::read> smooth [[texture(4)]],
                        texture2d<float, access::write> outR [[texture(5)]],
                        texture2d<float, access::write> outG [[texture(6)]],
                        texture2d<float, access::write> outB [[texture(7)]],
                        constant float *p [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  float l = lum.read(gid).r;
  float ls = smooth.read(gid).r;
  float t1 = p[1];
  float s = p[2];
  // Below the knee the ratio is exactly 1 (not (ls + (l − ls)) / l, an ulp off): untouched
  // pixels stay bit-identical. Above it the ratio is floored at 0, unlike hdrcomp: a dead pixel
  // (L ≈ 0) inside a compressed core would otherwise get a huge negative ratio.
  float ratio = 1.0f;
  if (ls > t1 && l > 1e-9f) {
    float compressed = t1 + s * asinh((ls - t1) / s);
    ratio = max((compressed + (l - ls)) / l, 0.0f);
  }
  outR.write(float4(r.read(gid).r * ratio), gid);
  if (p[0] < 3.0f) { return; }
  outG.write(float4(g.read(gid).r * ratio), gid);
  outB.write(float4(b.read(gid).r * ratio), gid);
}
