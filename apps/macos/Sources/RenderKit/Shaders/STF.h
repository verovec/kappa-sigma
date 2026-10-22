// The screen transfer function shared by the display and histogram kernels: the same arithmetic
// as the CPU oracle (STFParameters.display), compiled with fast-math off. A display transform only
// (R2): the planes are never modified.
#ifndef ASTROSTACK_STF_H
#define ASTROSTACK_STF_H
#include <metal_stdlib>

static inline float mtf(float m, float x) {
  if (x <= 0.0f) { return 0.0f; }
  if (x >= 1.0f) { return 1.0f; }
  if (x == m) { return 0.5f; }
  return ((m - 1.0f) * x) / ((2.0f * m - 1.0f) * x - m);
}

static inline float stf(float x, float c0, float m, float c1) {
  float range = c1 - c0;
  if (range <= 0.0f) { return x >= c1 ? 1.0f : 0.0f; }
  return mtf(m, metal::clamp((x - c0) / range, 0.0f, 1.0f));
}

#endif
