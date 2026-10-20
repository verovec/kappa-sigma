# Kappa-Sigma

Native macOS app for deep-sky astrophotography: stack your captures with Siril, then finish them in a
PixInsight-like Studio with real-time Metal previews — every setting visible, explained and yours.

**Status: work in progress (2026-10-20).** The app does not exist yet. This repository holds the design
(`docs/design/astrostack-macos.md`), the Go engine the app's core is being carved from (`internal/`,
`cmd/`), and the build/test gates. The previous web-based engine lives in the sibling repo
`stacking-astro`. Capture data, legacy runs and the master library live outside any repo in
`~/Documents/astro/{captures,runs,library}` and are read read-only.

## Prerequisites (host, macOS)

- Siril 1.4.x (`/Applications/Siril.app`), GraXpert, StarNet2 (your own install, never bundled)
- Go ≥ 1.23, `just`, `golangci-lint`
- Xcode 26 + Metal Toolchain (for the Swift app, from epic E10)

## Build and test (Go engine)

```sh
go build ./... && go vet ./... && go test ./...
```

Live tests (host Siril, byte-identity goldens) self-skip unless `ASTRO_GOLDEN_LIVE=1`.

## Name

Kappa-sigma clipping is the outlier rejection at the heart of every image stack.

## License

MIT — see `LICENSE`.
