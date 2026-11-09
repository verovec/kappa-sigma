// The proxy a drag renders on (card 0189): a plane reduced by an integer factor, and a reduced
// result brought back to the full size for the viewer.
//
// `downsampleBox`: each output pixel is the average of the finite values of its factor × factor
// cell (a ragged last cell over what it holds; NaN when nothing in it is finite) — the rule of
// ImageKit's `FITSFile.downsampled(pooling: .mean)`, summed in a fixed row-major order.
// `upsampleBilinear`: pixel centres aligned ((i + 0.5) · src / dst − 0.5), edges clamped.
#include <metal_stdlib>
using namespace metal;

kernel void downsampleBox(texture2d<float, access::read> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant uint &factor [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
  uint x0 = gid.x * factor, y0 = gid.y * factor;
  uint x1 = min(x0 + factor, src.get_width()), y1 = min(y0 + factor, src.get_height());
  float sum = 0.0f;
  uint count = 0;
  for (uint y = y0; y < y1; ++y) {
    for (uint x = x0; x < x1; ++x) {
      float value = src.read(uint2(x, y)).r;
      if (!isfinite(value)) { continue; }
      sum += value;
      count += 1;
    }
  }
  dst.write(count > 0 ? sum / float(count) : NAN, gid);
}

kernel void upsampleBilinear(texture2d<float, access::read> src [[texture(0)]],
                             texture2d<float, access::write> dst [[texture(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
  uint dstWidth = dst.get_width(), dstHeight = dst.get_height();
  if (gid.x >= dstWidth || gid.y >= dstHeight) { return; }
  int width = int(src.get_width()), height = int(src.get_height());
  float sx = (float(gid.x) + 0.5f) * float(width) / float(dstWidth) - 0.5f;
  float sy = (float(gid.y) + 0.5f) * float(height) / float(dstHeight) - 0.5f;
  int x0 = int(floor(sx)), y0 = int(floor(sy));
  float fx = sx - float(x0), fy = sy - float(y0);
  int xa = clamp(x0, 0, width - 1), xb = clamp(x0 + 1, 0, width - 1);
  int ya = clamp(y0, 0, height - 1), yb = clamp(y0 + 1, 0, height - 1);
  float top = src.read(uint2(xa, ya)).r * (1.0f - fx) + src.read(uint2(xb, ya)).r * fx;
  float bottom = src.read(uint2(xa, yb)).r * (1.0f - fx) + src.read(uint2(xb, yb)).r * fx;
  dst.write(top * (1.0f - fy) + bottom * fy, gid);
}
