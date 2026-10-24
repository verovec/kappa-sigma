// Line injection (card 0120): the emission lines added into the linear RGB base. Pinned against
// LineInjectionOracle in the tests; fast-math off.
#include <metal_stdlib>
using namespace metal;

// One line's contribution: q[0..2] = gain · share per plane, q[3] = k, q[4] = black. fmax: a
// NaN excess (a rejected line pixel) adds nothing rather than poisoning the base.
static float3 inject(float3 acc, float line, float reference, constant float *q) {
  float3 w = float3(q[0], q[1], q[2]);
  if (all(w == 0.0f)) { return acc; }
  // At k = 0 no reference is read: inf − 0·inf would turn a saturated line pixel into NaN.
  float continuum = q[3] == 0.0f ? 0.0f : q[3] * reference;
  float excess = fmax(line - continuum - q[4], 0.0f);
  // Nothing to add keeps the pixel's bits (+0 would turn a −0.0 base into +0.0).
  if (!(excess > 0.0f)) { return acc; }
  if (w.r != 0.0f) { acc.r += w.r * excess; }
  if (w.g != 0.0f) { acc.g += w.g * excess; }
  if (w.b != 0.0f) { acc.b += w.b * excess; }
  return acc;
}

// p[5·l .. 5·l+4] for Hα, [OIII], [SII]; each line's plane and reference at 6 + 2·l, 7 + 2·l.
kernel void lineInjection(texture2d<float, access::read> inR [[texture(0)]],
                          texture2d<float, access::read> inG [[texture(1)]],
                          texture2d<float, access::read> inB [[texture(2)]],
                          texture2d<float, access::write> outR [[texture(3)]],
                          texture2d<float, access::write> outG [[texture(4)]],
                          texture2d<float, access::write> outB [[texture(5)]],
                          texture2d<float, access::read> ha [[texture(6)]],
                          texture2d<float, access::read> haRef [[texture(7)]],
                          texture2d<float, access::read> oiii [[texture(8)]],
                          texture2d<float, access::read> oiiiRef [[texture(9)]],
                          texture2d<float, access::read> sii [[texture(10)]],
                          texture2d<float, access::read> siiRef [[texture(11)]],
                          constant float *p [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outR.get_width() || gid.y >= outR.get_height()) { return; }
  float3 acc = float3(inR.read(gid).r, inG.read(gid).r, inB.read(gid).r);
  acc = inject(acc, ha.read(gid).r, haRef.read(gid).r, p);
  acc = inject(acc, oiii.read(gid).r, oiiiRef.read(gid).r, p + 5);
  acc = inject(acc, sii.read(gid).r, siiRef.read(gid).r, p + 10);
  outR.write(float4(acc.r), gid);
  outG.write(float4(acc.g), gid);
  outB.write(float4(acc.b), gid);
}
