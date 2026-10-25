Makes the star colours true: Siril's SPCC (or PCC) measures the stars and sets one gain per channel.
Solve the image first; then pick your **sensor**, the **filter** of the capture and the **white reference**.
The panel shows the gains Siril applied and the stars it used; nothing else is tried if it fails.
Pitfall: on dual-band data there is no broadband white, so the dual-band profile ships it off; use **Colour balance** by hand.
On a broadband + dual-band stack it sees the broadband alone: **Line injection** comes after.
