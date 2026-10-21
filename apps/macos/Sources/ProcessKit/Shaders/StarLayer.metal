// Star layer (card 0055): stardesat's recomposition. The star layer is max(original − starless,
// 0) per channel; its chroma is scaled by k around the Rec. 709 luma; it is put back on the
// starless at presence r, additively (stardesat) or as a screen (PixInsight). Pinned against
// StarLayerOracle and stardesat's recorded stars_25/50/75 and haplus_final; fast-math off.
#include <metal_stdlib>
using namespace metal;

// p[0] chroma k · p[1] presence r · p[2] mode (0 additive, 1 screen)
kernel void starLayer(texture2d<float, access::read> origR [[texture(0)]],
                      texture2d<float, access::read> origG [[texture(1)]],
                      texture2d<float, access::read> origB [[texture(2)]],
                      texture2d<float, access::read> lessR [[texture(3)]],
                      texture2d<float, access::read> lessG [[texture(4)]],
                      texture2d<float, access::read> lessB [[texture(5)]],
                      texture2d<float, access::write> outR [[texture(6)]],
                      texture2d<float, access::write> outG [[texture(7)]],
                      texture2d<float, access::write> outB [[texture(8)]],
                      constant float *p [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  float3 original = float3(origR.read(gid).r, origG.read(gid).r, origB.read(gid).r);
  float3 starless = float3(lessR.read(gid).r, lessG.read(gid).r, lessB.read(gid).r);
  float3 stars = max(original - starless, 0.0f);
  float luma = 0.2126f * stars.r + 0.7152f * stars.g + 0.0722f * stars.b;
  float3 layer = p[1] * (luma + (stars - luma) * p[0]);
  float3 out = p[2] == 0.0f ? starless + layer
                            : 1.0f - (1.0f - starless) * (1.0f - clamp(layer, 0.0f, 1.0f));
  out = clamp(out, 0.0f, 1.0f);
  outR.write(float4(out.r), gid);
  outG.write(float4(out.g), gid);
  outB.write(float4(out.b), gid);
}
