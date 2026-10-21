# Documentation

| Topic | Where |
|-------|-------|
| Modules, host tools, data locations | [`architecture.md`](architecture.md) |
| Toolchain, recipes, tests, CI, conventions, workflow | [`development.md`](development.md) |
| Product and architecture design of AstroStack (the reference for every card) | [`design/astrostack-macos.md`](design/astrostack-macos.md) |
| Validated finishing values (v9 chain) the profiles derive from | [`design/stacking-params.reference.json`](design/stacking-params.reference.json) |
| Quality gates and the decisions of the Swift port | [`engineering/swift-quality-playbook.md`](engineering/swift-quality-playbook.md) |
| Project database schema | [`SCHEMA.md`](../apps/macos/Sources/ProjectKit/SCHEMA.md) |
| README artwork (logo, NGC 7000) | [`assets/`](assets/) |

Each module also has its own README under `apps/macos/Sources/<Module>/`, listed in
[`architecture.md`](architecture.md#modules).

The documentation of the legacy Go engine (architecture, modes, calibration, parameter tables) was
not migrated: it stays in the sibling repository `stacking-astro`, read only while its rules are
ported to Swift.
