// Grey morphology (card 0051, shared with 0052): one axis of a min (erosion) or max (dilation)
// over the window [i − r, i + r], clipped to the image like astrocomp's sepFilter. Pinned bit for
// bit against a van Herk / Gil-Werman CPU oracle in GreyMorphologyTests; fast-math off.
#include <metal_stdlib>
using namespace metal;

// window.x radius · window.y axis (0 = x, 1 = y) · window.z 1 for max (dilation), 0 for min
kernel void morphologyWindow(texture2d<float, access::read> src [[texture(0)]],
                             texture2d<float, access::write> dst [[texture(1)]],
                             constant int3 &window [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
  int2 step = window.y == 0 ? int2(1, 0) : int2(0, 1);
  int length = window.y == 0 ? int(src.get_width()) : int(src.get_height());
  int at = window.y == 0 ? int(gid.x) : int(gid.y);
  int low = max(at - window.x, 0);
  int high = min(at + window.x, length - 1);
  int2 origin = int2(gid) - step * at;
  float value = src.read(uint2(origin + step * low)).r;
  for (int k = low + 1; k <= high; ++k) {
    float sample = src.read(uint2(origin + step * k)).r;
    value = window.z != 0 ? max(value, sample) : min(value, sample);
  }
  dst.write(float4(value), gid);
}
