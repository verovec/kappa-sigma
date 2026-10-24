// Denoise (card 0115): the à-trous B3-spline starlet of StackKit's `Starlet`, a soft threshold
// per scale (StarletDenoiser's per-scale step), the coarse residual kept, then the denoised
// planes' luminance and colour changes put back at their own amounts. Pinned against
// DenoiseOracle (StackKit's CPU starlet); fast-math off.
#include <metal_stdlib>
using namespace metal;

// Half-sample symmetric reflection into [0, n): -1 -> 0, n -> n - 1 (Starlet.reflect).
static int reflectIndex(int index, int count) {
  if (count <= 1) { return 0; }
  int value = index;
  while (value < 0 || value >= count) {
    if (value < 0) { value = -value - 1; }
    if (value >= count) { value = 2 * count - value - 1; }
  }
  return value;
}

// (1/16)·(a + 4b + 6c + 4d + e), fused as Starlet.kernel fuses it.
static float b3(float a, float b, float c, float d, float e) {
  float sum = fma(4.0f, b, a);
  sum = fma(6.0f, c, sum);
  sum = fma(4.0f, d, sum);
  return (1.0f / 16.0f) * (sum + e);
}

// One B3 pass at dilation step along x (axis 0) or y (axis 1).
kernel void starletPass(texture2d<float, access::read> src [[texture(0)]],
                        texture2d<float, access::write> dst [[texture(1)]],
                        constant int2 &stepAxis [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
  int width = int(dst.get_width());
  int height = int(dst.get_height());
  if (int(gid.x) >= width || int(gid.y) >= height) { return; }
  int step = stepAxis.x;
  bool rows = stepAxis.y == 0;
  int count = rows ? width : height;
  int at = rows ? int(gid.x) : int(gid.y);
  float taps[5];
  for (int tap = 0; tap < 5; tap++) {
    int index = reflectIndex(at + (tap - 2) * step, count);
    uint2 position = rows ? uint2(index, gid.y) : uint2(gid.x, index);
    taps[tap] = src.read(position).r;
  }
  dst.write(float4(b3(taps[0], taps[1], taps[2], taps[3], taps[4])), gid);
}

// The share of each pixel kept as it is: the SNR of the scale-2 smooth above the median, in σ,
// through StarletDenoiser's smoothstep band. p[0] median · p[1] σ · p[2] low · p[3] high
kernel void denoiseProtection(texture2d<float, access::read> scaleTwo [[texture(0)]],
                              texture2d<float, access::write> mask [[texture(1)]],
                              constant float *p [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= mask.get_width() || gid.y >= mask.get_height()) { return; }
  float kept = 1.0f;
  if (p[1] > 0.0f) {
    float snr = (scaleTwo.read(gid).r - p[0]) / p[1];
    float ramp = clamp((snr - p[2]) / (p[3] - p[2]), 0.0f, 1.0f);
    kept = ramp * ramp * (3.0f - 2.0f * ramp);
  }
  mask.write(float4(kept), gid);
}

// One detail plane (fine − coarse) soft-thresholded, the protected share kept, added to the sum.
// p[0] threshold · p[1] first scale (1: the sum starts here) · p[2] protection on
kernel void denoiseDetail(texture2d<float, access::read> fine [[texture(0)]],
                          texture2d<float, access::read> coarse [[texture(1)]],
                          texture2d<float, access::read> mask [[texture(2)]],
                          texture2d<float, access::read_write> sum [[texture(3)]],
                          constant float *p [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= sum.get_width() || gid.y >= sum.get_height()) { return; }
  float detail = fine.read(gid).r - coarse.read(gid).r;
  float magnitude = fabs(detail) - p[0];
  float shrunk = magnitude <= 0.0f ? 0.0f : (detail < 0.0f ? -magnitude : magnitude);
  float kept = p[2] != 0.0f ? mask.read(gid).r : 0.0f;
  float value = fma(1.0f - kept, shrunk, kept * detail);
  float total = p[1] != 0.0f ? value : sum.read(gid).r + value;
  sum.write(float4(total), gid);
}

// The coarse residual added back: the denoised plane.
kernel void denoiseRecompose(texture2d<float, access::read> coarse [[texture(0)]],
                             texture2d<float, access::read_write> sum [[texture(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= sum.get_width() || gid.y >= sum.get_height()) { return; }
  sum.write(float4(coarse.read(gid).r + sum.read(gid).r), gid);
}

// The input moved toward the denoised planes (in place in `out`): the luminance (mean of the
// planes) change at the luminance amount, the rest (colour) at the chrominance amount; a mono
// plane takes the luminance amount. p[0] luminance amount · p[1] colour amount · p[2] planes
kernel void denoiseBlend(texture2d<float, access::read> inR [[texture(0)]],
                         texture2d<float, access::read> inG [[texture(1)]],
                         texture2d<float, access::read> inB [[texture(2)]],
                         texture2d<float, access::read_write> outR [[texture(3)]],
                         texture2d<float, access::read_write> outG [[texture(4)]],
                         texture2d<float, access::read_write> outB [[texture(5)]],
                         constant float *p [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  if (p[2] < 3.0f) {
    float input = inR.read(gid).r;
    outR.write(float4(input + p[0] * (outR.read(gid).r - input)), gid);
    return;
  }
  float3 input = float3(inR.read(gid).r, inG.read(gid).r, inB.read(gid).r);
  float3 output = float3(outR.read(gid).r, outG.read(gid).r, outB.read(gid).r);
  float luma = (input.r + input.g + input.b) / 3.0f;
  float lumaOut = (output.r + output.g + output.b) / 3.0f;
  float3 colourChange = (output - lumaOut) - (input - luma);
  float3 result = input + p[0] * (lumaOut - luma) + p[1] * colourChange;
  outR.write(float4(result.r), gid);
  outG.write(float4(result.g), gid);
  outB.write(float4(result.b), gid);
}
