// The parameter structs shared by every RenderKit shader: the single definition (swift-
// conventions.md). The Swift mirrors (DisplayUniforms.swift…) are pinned to these layouts by
// ShaderLayoutProbe, which reads every field back on the GPU. Plain float/uint fields only, so
// both sides lay them out identically without packing rules.
#ifndef ASTROSTACK_SHADER_TYPES_H
#define ASTROSTACK_SHADER_TYPES_H

struct DisplayUniforms {
  float shadows[4];       // STF c0 per channel (index 3 unused)
  float midtone[4];       // STF m per channel
  float highlights[4];    // STF c1 per channel
  unsigned int channels;  // 1 (mono: one plane shown grey) or 3
  unsigned int stfEnabled;      // 0: display is clamp(x)
  unsigned int clippingOverlay; // 1: x >= 1 tinted red, x <= 0 tinted blue
  unsigned int compareMode;     // 0 current, 1 reference everywhere, 2 reference left of splitX
  float splitX;           // view pixel column of the compare split
  float scale;            // image pixels per view pixel (1 = 1:1, 2 = zoomed out ×2)
  float originX;          // image coordinate of the view's top-left pixel
  float originY;
  float imageWidth;
  float imageHeight;
  float mipLevels;
  unsigned int flipRows;  // 1: stored row 0 is the bottom (ROWORDER BOTTOM-UP), shown last
  unsigned int maskOverlay; // 1: the mask (texture 7) tints the view red by half its value
  float canvasGrey;       // grey level of view pixels outside the image (R = G = B)
};

struct HistogramUniforms {
  unsigned int channels;
  unsigned int stride;    // sample every `stride` pixels in x and y (2 → quarter resolution)
  unsigned int originX;   // region: first sampled column and row (0, 0 for the whole image)
  unsigned int originY;
  unsigned int width;     // region size in pixels
  unsigned int height;
};

#endif
