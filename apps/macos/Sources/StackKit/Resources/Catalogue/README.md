# `openngc.csv` — object-type overlay (OpenNGC)

A slimmed snapshot of **OpenNGC** (https://github.com/mattiaverga/OpenNGC), the type / size /
surface-brightness / common-name database of the NGC and IC catalogues, taken as is from the legacy
engine's `internal/skycat/catalogue/openngc.csv` (card 0129). Siril's CSVs carry no type column;
`SkyCatalogue.load` lays this overlay over them by name.

It is **never a coordinate source**: the Siril lists own the coordinates. `Dup`, `NonEx` and star
rows were dropped when it was slimmed and only NGC/IC names kept, unpadded (`NGC0224` → `NGC224`) to
match Siril's rows. Columns: `name,type,majax,minax,posang,surfbr,hubble,messier,common`, `common`
names `/`-separated.

**Licence.** OpenNGC data is released under **CC-BY-SA-4.0** (© Mattia Verga and contributors).
Keep this attribution when redistributing. To refresh, re-slim `database_files/NGC.csv` from a
current OpenNGC release into the same columns.

Siril's own lists (`messier`, `ngc`, `ic`, `sh2`, `ldn`) are **not** copied here: they are read
from the installed Siril (one list, never a drifting copy).
