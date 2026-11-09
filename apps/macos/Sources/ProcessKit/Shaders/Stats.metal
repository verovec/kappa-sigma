// A layer's statistics on the GPU (card 0188): the finite extremes of a plane and the strided
// sample its median and MADN are computed from on the CPU (AutoSTF's rule) — what
// LayerStats.measured reads, without reading the plane back.
//
// Atomics are fine here: a minimum and a maximum are exact whatever the order the threads land
// in, so the kernel is deterministic; nothing is summed.
#include <metal_stdlib>
using namespace metal;

// A float's bits as an unsigned key ordered like the float (−0 below +0, as IEEE orders them).
inline uint orderedKey(float value) {
  uint bits = as_type<uint>(value);
  return (bits & 0x80000000u) ? ~bits : (bits | 0x80000000u);
}

// bounds[0] = the key of the smallest finite value, bounds[1] = of the largest; the caller
// starts them at 0xFFFFFFFF and 0, which stay when the plane holds nothing finite.
kernel void extremes(texture2d<float, access::read> plane [[texture(0)]],
                     device atomic_uint *bounds [[buffer(0)]],
                     uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= plane.get_width() || gid.y >= plane.get_height()) { return; }
  float value = plane.read(gid).r;
  if (!isfinite(value)) { return; }
  uint key = orderedKey(value);
  atomic_fetch_min_explicit(&bounds[0], key, memory_order_relaxed);
  atomic_fetch_max_explicit(&bounds[1], key, memory_order_relaxed);
}

// sample[i] = plane[i · stride] in row-major order, for i < count: the CPU measure's sample.
kernel void sampleStrided(texture2d<float, access::read> plane [[texture(0)]],
                          device float *sample [[buffer(0)]],
                          constant uint &stride [[buffer(1)]],
                          constant uint &count [[buffer(2)]],
                          uint gid [[thread_position_in_grid]]) {
  if (gid >= count) { return; }
  uint index = gid * stride;
  uint width = plane.get_width();
  sample[gid] = plane.read(uint2(index % width, index / width)).r;
}
