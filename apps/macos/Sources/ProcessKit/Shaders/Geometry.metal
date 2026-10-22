// Geometry (card 0090), one plane per dispatch. `geometry_exact` copies pixels through a
// whole-pixel map (crop, quarter turns, flips): bit-exact, no arithmetic on the values.
// `geometry_resample` turns the frame by a fine angle about its centre with an explicit kernel
// (bilinear, Keys bicubic a = -0.5, Lanczos-3 normalised); a pixel whose source falls outside
// the input is 0, kernel taps clamp to the edge. Fast-math off; the CPU oracle is the test's.
#include <metal_stdlib>
using namespace metal;

// m[0..3] inverse matrix, m[4..5] offset, in 1-based coordinates: in = M⁻¹·(out − t).
kernel void geometry_exact(
  texture2d<float, access::read> input [[texture(0)]],
  texture2d<float, access::write> output [[texture(1)]],
  constant int *m [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
  int2 shifted = int2(gid) + 1 - int2(m[4], m[5]);
  int2 source = int2(m[0] * shifted.x + m[1] * shifted.y, m[2] * shifted.x + m[3] * shifted.y) - 1;
  output.write(input.read(uint2(source)), gid);
}

static float weight(float distance, int kernelID) {
  float d = fabs(distance);
  if (kernelID == 0) { return max(0.0f, 1.0f - d); }
  if (kernelID == 1) {
    const float a = -0.5f;
    if (d <= 1.0f) { return ((a + 2.0f) * d - (a + 3.0f)) * d * d + 1.0f; }
    if (d < 2.0f) { return ((a * d - 5.0f * a) * d + 8.0f * a) * d - 4.0f * a; }
    return 0.0f;
  }
  if (d == 0.0f) { return 1.0f; }
  if (d >= 3.0f) { return 0.0f; }
  float pd = M_PI_F * d;
  return 3.0f * precise::sin(pd) * precise::sin(pd / 3.0f) / (pd * pd);
}

// p[0] cos, p[1] sin, p[2..3] output centre, p[4..5] input centre, p[6] kernel.
kernel void geometry_resample(
  texture2d<float, access::read> input [[texture(0)]],
  texture2d<float, access::write> output [[texture(1)]],
  constant float *p [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
  int width = int(input.get_width());
  int height = int(input.get_height());
  float dx = float(gid.x) - p[2];
  float dy = float(gid.y) - p[3];
  float sx = p[0] * dx + p[1] * dy + p[4];
  float sy = -p[1] * dx + p[0] * dy + p[5];
  if (sx < -0.5f || sx > float(width) - 0.5f || sy < -0.5f || sy > float(height) - 0.5f) {
    output.write(float4(0.0f), gid);
    return;
  }
  int kernelID = int(p[6]);
  int radius = kernelID == 0 ? 1 : (kernelID == 1 ? 2 : 3);
  int x0 = int(floor(sx));
  int y0 = int(floor(sy));
  float sum = 0.0f;
  float weights = 0.0f;
  for (int j = y0 - radius + 1; j <= y0 + radius; j++) {
    float wy = weight(sy - float(j), kernelID);
    for (int i = x0 - radius + 1; i <= x0 + radius; i++) {
      float w = weight(sx - float(i), kernelID) * wy;
      uint2 tap = uint2(clamp(i, 0, width - 1), clamp(j, 0, height - 1));
      sum += w * input.read(tap).r;
      weights += w;
    }
  }
  output.write(float4(kernelID == 2 ? sum / weights : sum), gid);
}
