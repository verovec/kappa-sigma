# CatalogTool

The executable `CatalogPlugin` runs at build time: `CatalogTool <catalog.xcstrings> <output folder>`.
It hands the catalog to `StringCatalog.CatalogCompiler`, writes one `<language>.lproj` table per
language, and fails the build with the reasons when the catalog fails the gate (a missing French or
English value never ships).

To extend: put the rule in `StringCatalog` (where it is tested), never here; this target only reads
its two arguments and reports.
