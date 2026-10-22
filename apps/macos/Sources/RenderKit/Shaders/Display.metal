// Display: linear float planes → displayed colour. The STF (STF.h) is a display transform only
// (R2): the planes are never modified. Same arithmetic as the CPU oracle (STFParameters.display),
// compiled with fast-math off.
#include <metal_stdlib>
#include "ShaderTypes.h"
#include "STF.h"
using namespace metal;

static float3 fetch(texture2d<float> r, texture2d<float> g, texture2d<float> b, float2 uv,
                    float lod, uint channels) {
  constexpr sampler s(coord::normalized, filter::nearest, mip_filter::nearest,
                      address::clamp_to_edge);
  float red = r.sample(s, uv, level(lod)).r;
  if (channels < 3) { return float3(red); }
  return float3(red, g.sample(s, uv, level(lod)).r, b.sample(s, uv, level(lod)).r);
}

kernel void display(texture2d<float> r [[texture(0)]], texture2d<float> g [[texture(1)]],
                    texture2d<float> b [[texture(2)]], texture2d<float> refR [[texture(3)]],
                    texture2d<float> refG [[texture(4)]], texture2d<float> refB [[texture(5)]],
                    texture2d<float, access::write> out [[texture(6)]],
                    texture2d<float, access::read> mask [[texture(7)]],
                    constant DisplayUniforms &u [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
  float2 image = float2(u.originX, u.originY) + (float2(gid) + 0.5f) * u.scale;
  if (image.x < 0.0f || image.y < 0.0f || image.x >= u.imageWidth || image.y >= u.imageHeight) {
    out.write(float4(float3(u.canvasGrey), 1.0f), gid);
    return;
  }
  if (u.flipRows != 0) { image.y = u.imageHeight - image.y; }
  float2 uv = image / float2(u.imageWidth, u.imageHeight);
  float lod = clamp(floor(log2(max(u.scale, 1.0f))), 0.0f, u.mipLevels - 1.0f);
  bool reference = u.compareMode == 1 || (u.compareMode == 2 && float(gid.x) < u.splitX);
  float3 v = reference ? fetch(refR, refG, refB, uv, lod, u.channels)
                       : fetch(r, g, b, uv, lod, u.channels);
  if (u.clippingOverlay != 0) {
    if (any(v >= 1.0f)) { out.write(float4(1.0f, 0.0f, 0.0f, 1.0f), gid); return; }
    if (any(v <= 0.0f)) { out.write(float4(0.0f, 0.0f, 1.0f, 1.0f), gid); return; }
  }
  float3 shown;
  for (uint c = 0; c < 3; ++c) {
    uint k = u.channels < 3 ? 0 : c;
    shown[c] = u.stfEnabled != 0 ? stf(v[c], u.shadows[k], u.midtone[k], u.highlights[k])
                                 : clamp(v[c], 0.0f, 1.0f);
  }
  if (u.maskOverlay != 0) {
    // The mask is in stored pixels: sample it where the image was sampled.
    float m = mask.read(uint2(min(uv * float2(mask.get_width(), mask.get_height()),
                                  float2(mask.get_width() - 1, mask.get_height() - 1)))).r;
    shown = shown * (1.0f - 0.5f * m) + float3(0.5f * m, 0.0f, 0.0f);
  }
  out.write(float4(shown, 1.0f), gid);
}

// Layout probe for ShaderLayoutTests: Swift fills every field with a distinct value; the GPU
// reads each field by name and writes its bits back in declaration order, then the sizes. Any
// layout drift between this header and the Swift mirrors shows as a wrong value.
kernel void shaderLayout(constant DisplayUniforms &d [[buffer(0)]],
                         constant HistogramUniforms &h [[buffer(1)]],
                         device uint *out [[buffer(2)]]) {
  uint i = 0;
  for (uint k = 0; k < 4; ++k) { out[i++] = as_type<uint>(d.shadows[k]); }
  for (uint k = 0; k < 4; ++k) { out[i++] = as_type<uint>(d.midtone[k]); }
  for (uint k = 0; k < 4; ++k) { out[i++] = as_type<uint>(d.highlights[k]); }
  out[i++] = d.channels;
  out[i++] = d.stfEnabled;
  out[i++] = d.clippingOverlay;
  out[i++] = d.compareMode;
  out[i++] = as_type<uint>(d.splitX);
  out[i++] = as_type<uint>(d.scale);
  out[i++] = as_type<uint>(d.originX);
  out[i++] = as_type<uint>(d.originY);
  out[i++] = as_type<uint>(d.imageWidth);
  out[i++] = as_type<uint>(d.imageHeight);
  out[i++] = as_type<uint>(d.mipLevels);
  out[i++] = d.flipRows;
  out[i++] = d.maskOverlay;
  out[i++] = as_type<uint>(d.canvasGrey);
  for (uint k = 0; k < 4; ++k) { out[i++] = as_type<uint>(h.shadows[k]); }
  for (uint k = 0; k < 4; ++k) { out[i++] = as_type<uint>(h.midtone[k]); }
  for (uint k = 0; k < 4; ++k) { out[i++] = as_type<uint>(h.highlights[k]); }
  out[i++] = h.channels;
  out[i++] = h.stride;
  out[i++] = h.originX;
  out[i++] = h.originY;
  out[i++] = h.width;
  out[i++] = h.height;
  out[i++] = h.stfEnabled;
  out[i++] = sizeof(DisplayUniforms);
  out[i++] = sizeof(HistogramUniforms);
}
