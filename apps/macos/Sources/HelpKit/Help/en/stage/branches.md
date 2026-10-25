A bundle that stacked several layers (broadband, Hα, OIII) gives each one a branch: its own history, before the layers are combined.
Pick a channel on the left: the viewer, the catalogue, Apply and Undo work on that layer only. Only per-layer linear processes run there (denoise, colour balance on the colour layer); the others say they act on the combined image.
The combined image reads every branch's head. After a branch edit, the steps that read it are flagged: Replay runs them again with their recorded values.
