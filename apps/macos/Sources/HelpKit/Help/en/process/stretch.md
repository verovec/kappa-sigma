The first non-linear step: makes the faint signal visible while the data are still linear.
**MTF** places the shadows a few σ below the background median and sends the median to the target background (Siril autostretch: −2.8σ, 0.25).
**GHS** lifts the range around the symmetry point; b shapes the curve, the protections keep shadows and highlights linear.
**asinh** brightens while keeping each pixel's colour ratios.
**Headroom** rolls the linear cores off below the ceiling first, so stars keep their colour.
