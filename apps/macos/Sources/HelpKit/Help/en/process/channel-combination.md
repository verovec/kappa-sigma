Builds the working RGB image from the bundle layers: each channel takes a layer, with a weight and a black point (**weight · max(layer − black, 0)**).
The RGB, HOO, SHO, HOS, Foraxx and LRGB palettes fill the channels; a missing layer greys the palette, never replaced.
**L** replaces the luminance at its opacity.
