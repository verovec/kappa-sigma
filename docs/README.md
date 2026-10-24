# Documentation

| Topic | Where |
|-------|-------|
| Modules, host tools, data locations | [`architecture.md`](architecture.md) |
| Toolchain, recipes, tests, CI, conventions, workflow | [`development.md`](development.md) |
| Product and architecture design of AstroStack (the reference for every card) | [`design/astrostack-macos.md`](design/astrostack-macos.md) |
| Preprocessing validated on M 31 and IC 1848 against the legacy runs (card 0058) | [`design/validation-e14.md`](design/validation-e14.md) |
| Validated finishing values (v9 chain) the profiles derive from | [`design/stacking-params.reference.json`](design/stacking-params.reference.json) |
| Quality gates and the decisions of the Swift port | [`engineering/swift-quality-playbook.md`](engineering/swift-quality-playbook.md) |
| Project database schema | [`SCHEMA.md`](../apps/macos/Sources/ProjectKit/SCHEMA.md) |
| README artwork (logo, NGC 7000) | [`assets/`](assets/) |

Each module also has its own README under `apps/macos/Sources/<Module>/`, listed in
[`architecture.md`](architecture.md#modules).

The legacy Go engine and its documentation were never migrated: every rule this app took from it is
now Swift, pinned by a recorded oracle, and the sibling repository `stacking-astro` is consulted
read only when a change touches one of those rules.
