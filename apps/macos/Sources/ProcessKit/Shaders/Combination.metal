// Channel combination (card 0054): each output slot = w · max(x − black, 0), where x is one
// layer plane or, for Foraxx's green, √(a·b) of two planes; then L replaces the luminance at its
// opacity. Pinned against a CPU oracle in CombinationTests; fast-math off.
#include <metal_stdlib>
using namespace metal;

// p[0..2] weight R, G, B · p[3..5] black R, G, B · p[6..8] 1 when the slot is √(a·b)
// p[9] L weight · p[10] L black · p[11] L opacity · p[12] 1 when an L layer is bound
kernel void combineChannels(texture2d<float, access::read> r [[texture(0)]],
                            texture2d<float, access::read> g [[texture(1)]],
                            texture2d<float, access::read> b [[texture(2)]],
                            texture2d<float, access::read> r2 [[texture(3)]],
                            texture2d<float, access::read> g2 [[texture(4)]],
                            texture2d<float, access::read> b2 [[texture(5)]],
                            texture2d<float, access::read> l [[texture(6)]],
                            texture2d<float, access::write> outR [[texture(7)]],
                            texture2d<float, access::write> outG [[texture(8)]],
                            texture2d<float, access::write> outB [[texture(9)]],
                            constant float *p [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  float a[3] = {r.read(gid).r, g.read(gid).r, b.read(gid).r};
  float second[3] = {r2.read(gid).r, g2.read(gid).r, b2.read(gid).r};
  float3 rgb;
  for (uint c = 0; c < 3; ++c) {
    float x = p[6 + c] != 0.0f ? sqrt(max(a[c] * second[c], 0.0f)) : a[c];
    rgb[c] = p[c] * max(x - p[3 + c], 0.0f);
  }
  if (p[12] != 0.0f) {
    float lum = p[9] * max(l.read(gid).r - p[10], 0.0f);
    float y = 0.2126f * rgb.r + 0.7152f * rgb.g + 0.0722f * rgb.b;
    float target = (1.0f - p[11]) * y + p[11] * lum;
    rgb = y > 0.0f ? rgb * (target / y) : float3(target);
  }
  outR.write(float4(rgb.r), gid);
  outG.write(float4(rgb.g), gid);
  outB.write(float4(rgb.b), gid);
}
