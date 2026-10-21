// Sky desaturation (card 0053): the sky_desat passes of the legacy chromasmooth.go, with its
// brightness-relative masks. The Gaussians run on Mask.metal's box pass (BoxGaussian.swift);
// the sky level and chroma σ come from the bundle statistics. Pinned against SkyDesatOracle;
// fast-math off.
#include <metal_stdlib>
using namespace metal;

static float smoothstepLegacy(float a, float b, float x) {
  if (x <= a) { return 0.0f; }
  if (x >= b) { return 1.0f; }
  float t = (x - a) / (b - a);
  return t * t * (3.0f - 2.0f * t);
}

// mean = (R + G + B) / 3, the luminance every stage preserves.
kernel void skyMean(texture2d<float, access::read> inR [[texture(0)]],
                    texture2d<float, access::read> inG [[texture(1)]],
                    texture2d<float, access::read> inB [[texture(2)]],
                    texture2d<float, access::write> mean [[texture(3)]],
                    uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= mean.get_width() || gid.y >= mean.get_height()) { return; }
  mean.write(float4((inR.read(gid).r + inG.read(gid).r + inB.read(gid).r) / 3.0f), gid);
}

// Star weight: smoothstep of the local peak (lumS − lumC) / sky.
// p[0] star low · p[1] star high · p[2] sky level
kernel void skyStarWeight(texture2d<float, access::read> lumS [[texture(0)]],
                          texture2d<float, access::read> lumC [[texture(1)]],
                          texture2d<float, access::write> weight [[texture(2)]],
                          constant float *p [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= weight.get_width() || gid.y >= weight.get_height()) { return; }
  float peak = (lumS.read(gid).r - lumC.read(gid).r) / p[2];
  weight.write(float4(smoothstepLegacy(p[0], p[1], peak)), gid);
}

// The star-masked residual (c − mean)(1 − star) of one channel, blurred into its coarse field.
kernel void skyResidual(texture2d<float, access::read> channel [[texture(0)]],
                        texture2d<float, access::read> mean [[texture(1)]],
                        texture2d<float, access::read> weight [[texture(2)]],
                        texture2d<float, access::write> residual [[texture(3)]],
                        uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= residual.get_width() || gid.y >= residual.get_height()) { return; }
  float d = (channel.read(gid).r - mean.read(gid).r) * (1.0f - weight.read(gid).r);
  residual.write(float4(d), gid);
}

// True within `radius` 4-neighbour steps of a mean above `level` (the legacy dilated core mask).
static bool nearCore(texture2d<float, access::read> mean, uint2 gid, int radius, float level) {
  int2 size = int2(mean.get_width(), mean.get_height());
  for (int dy = -radius; dy <= radius; ++dy) {
    for (int dx = -radius; dx <= radius; ++dx) {
      if (abs(dx) + abs(dy) > radius) { continue; }
      int2 at = int2(gid) + int2(dx, dy);
      if (any(at < int2(0)) || any(at >= size)) { continue; }
      if (mean.read(uint2(at)).r > level) { return true; }
    }
  }
  return false;
}

// p[0] strength · p[1] 1 for keep-cool · p[2] chroma σ · p[3] sky level
// p[4] nebula low · p[5] nebula high · p[6] floor low · p[7] floor high
// p[8] core level · p[9] core guard radius
kernel void skyDesat(texture2d<float, access::read> inR [[texture(0)]],
                     texture2d<float, access::read> inG [[texture(1)]],
                     texture2d<float, access::read> inB [[texture(2)]],
                     texture2d<float, access::write> outR [[texture(3)]],
                     texture2d<float, access::write> outG [[texture(4)]],
                     texture2d<float, access::write> outB [[texture(5)]],
                     texture2d<float, access::read> mean [[texture(6)]],
                     texture2d<float, access::read> lumC [[texture(7)]],
                     texture2d<float, access::read> weight [[texture(8)]],
                     texture2d<float, access::read> smR [[texture(9)]],
                     texture2d<float, access::read> smG [[texture(10)]],
                     texture2d<float, access::read> smB [[texture(11)]],
                     constant float *p [[buffer(0)]],
                     uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  float3 c = float3(inR.read(gid).r, inG.read(gid).r, inB.read(gid).r);
  if (!nearCore(mean, gid, int(p[9]), p[8])) {
    float m = mean.read(gid).r;
    float star = weight.read(gid).r;
    float rel = (lumC.read(gid).r - p[3]) / p[3];
    float3 sm = float3(smR.read(gid).r, smG.read(gid).r, smB.read(gid).r);
    float w1 = p[0] * (1.0f - star) * (1.0f - smoothstepLegacy(p[4], p[5], rel));
    if (p[1] != 0.0f) {
      float dev = (c.r - c.b) - (sm.r - sm.b);
      w1 *= smoothstepLegacy(-p[2], p[2], dev);
    }
    float floorKept = 1.0f - p[0] * (1.0f - star) * (1.0f - smoothstepLegacy(p[6], p[7], rel));
    float3 chroma = c - m;
    chroma += w1 * (sm - chroma);
    chroma *= floorKept;
    c = m + chroma;
  }
  outR.write(float4(c.r), gid);
  outG.write(float4(c.g), gid);
  outB.write(float4(c.b), gid);
}
