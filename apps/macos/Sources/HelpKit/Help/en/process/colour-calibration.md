Makes star colours true: Siril's SPCC (or PCC) measures the stars and sets one gain per channel.
Solve the image first, then choose the **sensor** (the header's camera is offered), **filter** and **white reference**; a mono stack asks for its sensor and red, green, blue filters.
The panel shows Siril's gains and stars; nothing else is tried on failure.
Pitfall: dual-band data has no broadband white (profile ships it off); use **Colour balance**.
Before **Line injection**, it sees only the broadband of BB + dual-band stacks.
