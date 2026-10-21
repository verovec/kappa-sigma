// Emission screens (card 0051): astrocomp's HOO-over-broadband chain. Every coefficient is
// computed on the CPU (LineStretch.swift) from the panel values and the bundle statistics; the
// opening and smoothing between the two kernels are Morphology.metal and maskBoxBlur. Pinned
// against ScreensOracle and astrocomp's screens_only render of run #78; fast-math off.
#include <metal_stdlib>
using namespace metal;

static float mtf(float x, float m) {
  if (x <= 0.0f) { return 0.0f; }
  if (x >= 1.0f) { return 1.0f; }
  return (m - 1.0f) * x / ((2.0f * m - 1.0f) * x - m);
}

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
  float x = mtf((v - p[2]) / (1.0f - p[2]), p[3]);
  if (p[4] > 0.0f) { x = max((x - p[4]) / (1.0f - p[4]), 0.0f); }
  if (p[5] > 1.0f) {
    // astrocomp's soft shoulder: identity to the knee, then tanh towards the ceiling.
    const float knee = 0.60f, span = 0.98f - 0.60f;
    x *= p[5];
    if (x > knee) { x = knee + span * tanh((x - knee) / span); }
  }
  out.write(float4(x), gid);
}

static float3 screen(float3 base, float value, constant float *q) {
  if (q[0] <= 0.0f || value <= 0.0f) { return base; }
  return base + q[0] * value * float3(q[1], q[2], q[3]) * (1.0f - base);
}

// p[4l] opacity α (0: off), p[4l + 1..3] tint of line l, in Hα, [OIII], [SII] order.
kernel void screenBlend(texture2d<float, access::read> inR [[texture(0)]],
                        texture2d<float, access::read> inG [[texture(1)]],
                        texture2d<float, access::read> inB [[texture(2)]],
                        texture2d<float, access::read> line0 [[texture(3)]],
                        texture2d<float, access::read> line1 [[texture(4)]],
                        texture2d<float, access::read> line2 [[texture(5)]],
                        texture2d<float, access::write> outR [[texture(6)]],
                        texture2d<float, access::write> outG [[texture(7)]],
                        texture2d<float, access::write> outB [[texture(8)]],
                        constant float *p [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  float3 rgb = float3(inR.read(gid).r, inG.read(gid).r, inB.read(gid).r);
  rgb = screen(rgb, line0.read(gid).r, p);
  rgb = screen(rgb, line1.read(gid).r, p + 4);
  rgb = screen(rgb, line2.read(gid).r, p + 8);
  outR.write(float4(rgb.r), gid);
  outG.write(float4(rgb.g), gid);
  outB.write(float4(rgb.b), gid);
}
