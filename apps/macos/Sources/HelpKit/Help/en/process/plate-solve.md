Finds where the image points in the sky: the pixel readout then shows RA/Dec, and colour calibration can follow.
Give the **centre** first (take the header's suggestion, or type 00 42 44 and +41 16 09), then the **focal length** and **pixel size**.
Siril matches the stars with the local Gaia catalogue; no pixel changes, the solution stays with the step.
Pitfall: a wrong focal length or a centre degrees away fails; Siril's reason is shown and nothing else is tried.
