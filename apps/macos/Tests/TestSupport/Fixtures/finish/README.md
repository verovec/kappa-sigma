# Finishing oracles (card 0067)

`manifest.json` pins the PO's validated v9 "HaPlus" finishing chain: hdrcomp → astrocomp →
StarNet2 → stardesat (k 0.25, tiers 25/50/75). It ran on run #78 (`M_31/20261018_191749`, 76 BB +
34 DB frames) and on a 1024×768 centre crop of its layers. Only this text is committed. The
images, the crop layers and the tool sources live in `~/Documents/astro/fixtures/finish/`
(data rule R7), with `SHA256SUMS`.

Stages: `hdr_only` (hdrcomp FITS), `screens_only` (astrocomp `-sat 0`), `haplus_full`,
`starless`, `haplus_final` (stardesat r 1), `stars_25/50/75`. Each stage records its flags and
inputs, and the hash and size of `full/<stage>` and `crop/<stage>`. Parity tests read them
through `FinishOracle` and skip where the folder is absent (CI). `LiveFinishOracleTests` checks
every hash and size.

## Regenerate

```sh
scripts/record-finish-oracle.sh      # Go, Siril 1.4, /usr/local/bin/starnet2
cp ~/Documents/astro/fixtures/finish/manifest.json apps/macos/Tests/TestSupport/Fixtures/finish/
```

The script builds the Go tools from copies kept in the fixtures folder. The sources are
kappa-sigma's gitignored `tasks-context/tools` plus the legacy `internal/imgops`, read only. No Go
enters this repo and nothing is written into the run folder. Re-recording changes the hashes:
justify it in the PR body (`Test-change:`).
