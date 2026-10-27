// Emission screens (card 0051): astrocomp's HOO-over-broadband chain. Every coefficient is
// computed on the CPU (LineStretch.swift) from the panel values and the bundle statistics; the
// opening and smoothing between the two kernels are Morphology.metal and maskBoxBlur. Pinned
// against ScreensOracle and astrocomp's screens_only render of run #78; fast-math off.
#include <metal_stdlib>
#include "STF.h"
#include "Lines.h"
using namespace metal;

// p[0] 1 to subtract the continuum · p[1] k · p[2] shadows c · p[3] midtone m · p[4] black point
// p[5] boost (≤ 1: none)
kernel void screenLinePrepare(texture2d<float, access::read> line [[texture(0)]],
                              texture2d<float, access::read> reference [[texture(1)]],
                              texture2d<float, access::write> out [[texture(2)]],
                              constant float *p [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
  float v = line.read(gid).r;
  if (p[0] != 0.0f) { v = max(v - p[1] * reference.read(gid).r, 0.0f); }
  float x = mtf(p[3], (v - p[2]) / (1.0f - p[2]));
  if (p[4] > 0.0f) { x = max((x - p[4]) / (1.0f - p[4]), 0.0f); }
  if (p[5] > 1.0f) {
    // astrocomp's soft shoulder: identity to the knee, then tanh towards the ceiling.
    const float knee = 0.60f, span = 0.98f - 0.60f;
    x *= p[5];
    if (x > knee) { x = knee + span * tanh((x - knee) / span); }
  }
  out.write(float4(x), gid);
}

static float3 screen(float3 base, float value, constant ScreenLine &q) {
  if (q.alpha <= 0.0f || value <= 0.0f) { return base; }
  return base + q.alpha * value * float3(q.tint[0], q.tint[1], q.tint[2]) * (1.0f - base);
}

// The `count` bound lines in screen order (card 0136: an invisible line is not bound), line l's
// prepared layer at line[l], its opacity and tint at p[l]; outputs after the line slots.
kernel void screenBlend(texture2d<float, access::read> inR [[texture(0)]],
                        texture2d<float, access::read> inG [[texture(1)]],
                        texture2d<float, access::read> inB [[texture(2)]],
                        array<texture2d<float, access::read>, MAX_LINES> line [[texture(3)]],
                        texture2d<float, access::write> outR [[texture(3 + MAX_LINES)]],
                        texture2d<float, access::write> outG [[texture(4 + MAX_LINES)]],
                        texture2d<float, access::write> outB [[texture(5 + MAX_LINES)]],
                        constant ScreenLine *p [[buffer(0)]],
                        constant uint &count [[buffer(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  float3 rgb = float3(inR.read(gid).r, inG.read(gid).r, inB.read(gid).r);
  for (uint l = 0; l < count; ++l) { rgb = screen(rgb, line[l].read(gid).r, p[l]); }
  outR.write(float4(rgb.r), gid);
  outG.write(float4(rgb.g), gid);
  outB.write(float4(rgb.b), gid);
}
