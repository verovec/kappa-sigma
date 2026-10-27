// Line injection (card 0120): the emission lines added into the linear RGB base. Pinned against
// LineInjectionOracle in the tests; fast-math off.
#include <metal_stdlib>
#include "Lines.h"
using namespace metal;

// One line's contribution: q.weight = gain · share per plane, q.k the continuum scale, q.black.
static float3 inject(float3 acc, float line, float reference, constant InjectLine &q) {
  float3 w = float3(q.weight[0], q.weight[1], q.weight[2]);
  if (all(w == 0.0f)) { return acc; }
  // At k = 0 no reference is read: inf − 0·inf would turn a saturated line pixel into NaN.
  float continuum = q.k == 0.0f ? 0.0f : q.k * reference;
  float excess = line - continuum - q.black;
  // Only a positive excess adds: none keeps the pixel's bits (+0 would turn a −0.0 base into
  // +0.0), and a NaN one (a rejected line pixel) never poisons the base.
  if (!(excess > 0.0f)) { return acc; }
  if (w.r != 0.0f) { acc.r += w.r * excess; }
  if (w.g != 0.0f) { acc.g += w.g * excess; }
  if (w.b != 0.0f) { acc.b += w.b * excess; }
  return acc;
}

// The `count` bound lines in canonical order (card 0136: a line that adds nothing is not bound),
// line l's plane and reference at lines[2l], lines[2l + 1], its values at p[l].
kernel void lineInjection(texture2d<float, access::read> inR [[texture(0)]],
                          texture2d<float, access::read> inG [[texture(1)]],
                          texture2d<float, access::read> inB [[texture(2)]],
                          texture2d<float, access::write> outR [[texture(3)]],
                          texture2d<float, access::write> outG [[texture(4)]],
                          texture2d<float, access::write> outB [[texture(5)]],
                          array<texture2d<float, access::read>, 2 * MAX_LINES> lines [[texture(6)]],
                          constant InjectLine *p [[buffer(0)]],
                          constant uint &count [[buffer(1)]],
                          uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  float3 acc = float3(inR.read(gid).r, inG.read(gid).r, inB.read(gid).r);
  for (uint l = 0; l < count; ++l) {
    acc = inject(acc, lines[2 * l].read(gid).r, lines[2 * l + 1].read(gid).r, p[l]);
  }
  outR.write(float4(acc.r), gid);
  outG.write(float4(acc.g), gid);
  outB.write(float4(acc.b), gid);
}
