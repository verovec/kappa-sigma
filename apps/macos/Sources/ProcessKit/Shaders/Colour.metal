// Colour processes (card 0053): saturation, curves and colour balance share one library — they
// share the HSL helpers, and a runtime-compiled source has no #include. Pinned against
// ColourOracle / CurvesOracle in the tests; fast-math off.
#include <metal_stdlib>
using namespace metal;

// astrocomp's hueOf, in turns (mx != mn).
static float hueOf(float3 c, float mx, float mn) {
  float d = mx - mn;
  float hue;
  if (mx == c.r) {
    hue = (c.g - c.b) / d;
    if (hue < 0.0f) { hue += 6.0f; }
  } else if (mx == c.g) {
    hue = (c.b - c.r) / d + 2.0f;
  } else {
    hue = (c.r - c.g) / d + 4.0f;
  }
  return hue / 6.0f;
}

static float hslChannel(float t, float p, float q) {
  if (t < 0.0f) { t += 1.0f; }
  if (t > 1.0f) { t -= 1.0f; }
  if (t < 1.0f / 6.0f) { return p + (q - p) * 6.0f * t; }
  if (t < 1.0f / 2.0f) { return q; }
  if (t < 2.0f / 3.0f) { return p + (q - p) * (2.0f / 3.0f - t) * 6.0f; }
  return p;
}

// astrocomp's hslToRGB.
static float3 hslToRGB(float hue, float s, float l) {
  if (s == 0.0f) { return float3(l); }
  float q = l < 0.5f ? l * (1.0f + s) : l + s - l * s;
  float p = 2.0f * l - q;
  return float3(hslChannel(hue + 1.0f / 3.0f, p, q), hslChannel(hue, p, q),
                hslChannel(hue - 1.0f / 3.0f, p, q));
}

// HSL saturation of c (mx != mn), astrocomp's formula.
static float hslSaturation(float mx, float mn, float l) {
  return l <= 0.5f ? (mx - mn) / (mx + mn) : (mx - mn) / (2.0f - mx - mn);
}

// saturationMaskLUT: 0 to low, a ramp to high, 1 to the roll-off, then down to floor at white.
static float bandMask(float x, constant float *p) {
  float v;
  if (x <= p[2]) {
    v = 0.0f;
  } else if (x < p[3]) {
    v = (x - p[2]) / (p[3] - p[2]);
  } else if (x <= p[4]) {
    v = 1.0f;
  } else {
    v = 1.0f - (x - p[4]) / (1.0f - p[4]) * (1.0f - p[5]);
  }
  return clamp(v, 0.0f, 1.0f);
}

// starDesatMaskLUT: 0 to low, a ramp to 1 at high.
static float starMask(float x, float low, float high) {
  float v = x <= low ? 0.0f : (x < high ? (x - low) / (high - low) : 1.0f);
  return clamp(v, 0.0f, 1.0f);
}

// p[0] amount · p[1] 1 when masked · p[2..5] band low, high, roll-off, floor
// p[6] star desat · p[7] star low · p[8] star high · p[9] luma desat k
kernel void saturation(texture2d<float, access::read> inR [[texture(0)]],
                       texture2d<float, access::read> inG [[texture(1)]],
                       texture2d<float, access::read> inB [[texture(2)]],
                       texture2d<float, access::write> outR [[texture(3)]],
                       texture2d<float, access::write> outG [[texture(4)]],
                       texture2d<float, access::write> outB [[texture(5)]],
                       constant float *p [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  float3 c = float3(inR.read(gid).r, inG.read(gid).r, inB.read(gid).r);
  if (p[0] != 0.0f || p[6] != 0.0f) {
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    float l = (mx + mn) / 2.0f;
    if (mx != mn) {
      float s = hslSaturation(mx, mn, l);
      float hue = hueOf(c, mx, mn);
      s *= 1.0f + p[0] * (p[1] != 0.0f ? bandMask(l, p) : 1.0f);
      s = min(s, 1.0f);
      s *= 1.0f - p[6] * starMask(l, p[7], p[8]);
      c = hslToRGB(hue, s, l);
    }
  }
  if (p[9] != 1.0f) {
    float luma = 0.2126f * c.r + 0.7152f * c.g + 0.0722f * c.b;
    c = clamp(luma + (c - luma) * p[9], 0.0f, 1.0f);
  }
  outR.write(float4(c.r), gid);
  outG.write(float4(c.g), gid);
  outB.write(float4(c.b), gid);
}

// Linear interpolation in row `row` of the curves LUT (1024 samples over [0, 1]).
static float lookup(texture2d<float, access::read> lut, uint row, float x) {
  float t = clamp(x, 0.0f, 1.0f) * float(lut.get_width() - 1);
  uint index = min(uint(t), lut.get_width() - 2);
  float frac = t - float(index);
  float a = lut.read(uint2(index, row)).r;
  float b = lut.read(uint2(index + 1, row)).r;
  return a + (b - a) * frac;
}

// p[0] planes · p[1..6] 1 when the RGB, R, G, B, luminance, saturation curve is active
kernel void curves(texture2d<float, access::read> inR [[texture(0)]],
                   texture2d<float, access::read> inG [[texture(1)]],
                   texture2d<float, access::read> inB [[texture(2)]],
                   texture2d<float, access::write> outR [[texture(3)]],
                   texture2d<float, access::write> outG [[texture(4)]],
                   texture2d<float, access::write> outB [[texture(5)]],
                   texture2d<float, access::read> lut [[texture(6)]],
                   constant float *p [[buffer(0)]],
                   uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  if (p[0] < 3.0f) {
    float v = inR.read(gid).r;
    if (p[1] != 0.0f) { v = lookup(lut, 0, v); }
    if (p[5] != 0.0f) { v = lookup(lut, 4, v); }
    outR.write(float4(v), gid);
    return;
  }
  float3 c = float3(inR.read(gid).r, inG.read(gid).r, inB.read(gid).r);
  if (p[1] != 0.0f) { c = float3(lookup(lut, 0, c.r), lookup(lut, 0, c.g), lookup(lut, 0, c.b)); }
  if (p[2] != 0.0f) { c.r = lookup(lut, 1, c.r); }
  if (p[3] != 0.0f) { c.g = lookup(lut, 2, c.g); }
  if (p[4] != 0.0f) { c.b = lookup(lut, 3, c.b); }
  if (p[5] != 0.0f) {
    float luma = 0.2126f * c.r + 0.7152f * c.g + 0.0722f * c.b;
    c = clamp(c + (lookup(lut, 4, luma) - luma), 0.0f, 1.0f);
  }
  if (p[6] != 0.0f) {
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    if (mx != mn) {
      float l = (mx + mn) / 2.0f;
      c = hslToRGB(hueOf(c, mx, mn), lookup(lut, 5, hslSaturation(mx, mn, l)), l);
    }
  }
  outR.write(float4(c.r), gid);
  outG.write(float4(c.g), gid);
  outB.write(float4(c.b), gid);
}

// p[0..2] background offsets · p[3..5] gains: out = (in + offset) · gain
kernel void colourBalance(texture2d<float, access::read> inR [[texture(0)]],
                          texture2d<float, access::read> inG [[texture(1)]],
                          texture2d<float, access::read> inB [[texture(2)]],
                          texture2d<float, access::write> outR [[texture(3)]],
                          texture2d<float, access::write> outG [[texture(4)]],
                          texture2d<float, access::write> outB [[texture(5)]],
                          constant float *p [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  outR.write(float4((inR.read(gid).r + p[0]) * p[3]), gid);
  outG.write(float4((inG.read(gid).r + p[1]) * p[4]), gid);
  outB.write(float4((inB.read(gid).r + p[2]) * p[5]), gid);
}
