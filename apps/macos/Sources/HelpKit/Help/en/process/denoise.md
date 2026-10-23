Removes noise on linear data, before the stretch: the image is split into scales of 1, 2, 4 and 8 px, each thresholded at its **strength** in σ of the noise as it shows at that scale.
That σ follows the **noise level**, offered as measured on the image; 0 removes nothing.
**Amount** 0 leaves the image untouched; 1 applies the whole result.
**Protect stars** keeps what stands 5 to 10 noise levels above the background.
The **luminance** and **colour** amounts (advanced) dose the two parts.
