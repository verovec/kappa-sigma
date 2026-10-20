// Stretch (card 0050): an optional highlight headroom cap (legacy CompressHighlights: luminance
// 0.299/0.587/0.114, tanh shoulder from the knee to the ceiling, every channel scaled alike),
// then MTF, GHS or asinh. Every coefficient is computed on the CPU from the panel values and the
// bundle statistics (StretchUniforms.swift); pinned against StretchOracle; fast-math off.
#include <metal_stdlib>
using namespace metal;

// p[0] mode (0 MTF, 1 GHS, 2 asinh) · p[1] planes (1 or 3) · p[2] headroom ceiling · p[3] knee
// p[4 + 3c] c0, p[5 + 3c] 1 / (1 − c0), p[6 + 3c] midtone m of plane c
// p[13..23] GHS: b, D, LP, SP, HP, f(0), 1 / (f(1) − f(0)), T(SP−LP), T′(SP−LP), T(HP−SP), T′(HP−SP)
// p[24..26] asinh: β, black point, 1 / asinh(β)

static float mtf(float x, float m) {
  if (x <= 0.0f) { return 0.0f; }
  if (x >= 1.0f) { return 1.0f; }
  return (m - 1.0f) * x / ((2.0f * m - 1.0f) * x - m);
}

static float luminance(float3 rgb, uint planes) {
  return planes == 3 ? 0.299f * rgb.r + 0.587f * rgb.g + 0.114f * rgb.b : rgb.r;
}

static float3 headroom(float3 rgb, uint planes, float ceiling, float knee) {
  if (ceiling <= 0.0f || ceiling >= 1.0f) { return rgb; }
  float lum = luminance(rgb, planes);
  if (lum <= knee) { return rgb; }
  float compressed = knee + (ceiling - knee) * tanh((lum - knee) / (ceiling - knee));
  return rgb * (compressed / lum);
}

// The GHS base transform T(x) of local intensity b and strength d.
static float ghsBase(float x, float b, float d) {
  if (b == -1.0f) { return log(1.0f + d * x); }
  if (b < 0.0f) { return (1.0f - pow(1.0f - b * d * x, (b + 1.0f) / b)) / (d * (b + 1.0f)); }
  if (b == 0.0f) { return 1.0f - exp(-d * x); }
  return 1.0f - pow(1.0f + b * d * x, -1.0f / b);
}

static float ghs(float x, constant float *g) {
  x = clamp(x, 0.0f, 1.0f);
  float b = g[0], d = g[1], lp = g[2], sp = g[3], hp = g[4];
  if (d <= 0.0f) { return x; }
  float f;
  if (x < lp) {
    f = -g[7] + g[8] * (x - lp);
  } else if (x < sp) {
    f = -ghsBase(sp - x, b, d);
  } else if (x < hp) {
    f = ghsBase(x - sp, b, d);
  } else {
    f = g[9] + g[10] * (x - hp);
  }
  return (f - g[5]) * g[6];
}

kernel void stretch(texture2d<float, access::read> inR [[texture(0)]],
                    texture2d<float, access::read> inG [[texture(1)]],
                    texture2d<float, access::read> inB [[texture(2)]],
                    texture2d<float, access::write> outR [[texture(3)]],
                    texture2d<float, access::write> outG [[texture(4)]],
                    texture2d<float, access::write> outB [[texture(5)]],
                    constant float *p [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  uint planes = uint(p[1]);
  float3 rgb = float3(inR.read(gid).r, inG.read(gid).r, inB.read(gid).r);
  rgb = headroom(rgb, planes, p[2], p[3]);
  float3 out = rgb;
  if (p[0] == 0.0f) {
    for (uint c = 0; c < planes; ++c) {
      out[c] = mtf((rgb[c] - p[4 + 3 * c]) * p[5 + 3 * c], p[6 + 3 * c]);
    }
  } else if (p[0] == 1.0f) {
    for (uint c = 0; c < planes; ++c) { out[c] = ghs(rgb[c], p + 13); }
  }
  outR.write(float4(out.r), gid);
  if (planes == 3) {
    outG.write(float4(out.g), gid);
    outB.write(float4(out.b), gid);
  }
}
