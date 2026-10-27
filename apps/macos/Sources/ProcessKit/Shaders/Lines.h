// The per-line parameters of the line kernels (card 0136): the single definition. The Swift
// mirror is LineKernels.swift, pinned by LinesHeaderTests. Plain float fields only, so both sides
// lay them out identically without packing rules.
#ifndef ASTROSTACK_LINES_H
#define ASTROSTACK_LINES_H

// The line slots of the injection and screen kernels: every narrowband filter of the catalogue
// fits (LinesHeaderTests), with room left for the next ones.
#define MAX_LINES 8

// One injected line: weight[p] = gain · share of base plane p, k the continuum scale, black the
// line's black point.
struct InjectLine {
  float weight[3];
  float k;
  float black;
};

// One screened line: alpha = opacity · narrowband blend (0: off), tint the line's colour.
struct ScreenLine {
  float alpha;
  float tint[3];
};

#endif
