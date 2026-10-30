# gentoo-goose

Gentoo overlay providing `dev-util/goose` (aaif-goose/goose) - a local, extensible MCP-based AI agent. Self-maintained for kwasek404 (independent of third-party overlays).

## Consume

Add to `/etc/portage/repos.conf`:

```
[gentoo-goose]
location = /var/db/repos/gentoo-goose
sync-type = git
sync-uri = https://github.com/kwasek404/gentoo-goose.git
```

Then: `emerge --sync gentoo-goose` and `emerge dev-util/goose` (requires the `~amd64` keyword).

## Build

The ebuild uses `cargo.eclass` (`CRATES` + `GIT_CRATES`); dependencies are fetched from crates.io plus the pinned `cudaforge` git revision at build time. The package is built with `--no-default-features --features code-mode,rustls-tls --bin goose` (code-mode is a pure-Rust JS engine, so the build is quick).

## GUI (desktop app)

`IUSE="gui"` (off by default). With `gui`, the ebuild also installs the
Electron-based desktop app as `/usr/lib/Goose` (launcher `/usr/bin/Goose`,
menu entry `Goose.desktop`).

The app is **not built from source**: it lives in `ui/desktop` (Electron
Forge + Vite + React), outside the cargo workspace, and needs a node/pnpm
toolchain plus an Electron runtime that are not part of this overlay. Upstream
builds, e2e-tests and publishes the bundle as a `.deb` with every release, so
the ebuild repacks the official `goose_${PV}_amd64.deb` release artifact
(hash-pinned in the fat Manifest, like everything else).

The bundle is self-contained: it carries its own Electron runtime and a copy
of the `goose` CLI in `resources/bin/goose` (same release), so it does not use
the source-built CLI installed by the ebuild.

Self-update is disabled: the in-app updater would swap the install directory
with a GitHub download, bypassing Portage. The ebuild drops a
`PORTAGE_MANAGED` marker file into the install root, which makes the
updater's install-directory check refuse to run. Update the app the normal
way: the CI below bumps the ebuild on new releases, then `emerge`/
`gentoo-update`.

Trust model: the `.deb` is the same official release artifact upstream
publishes for Debian; it is not additionally signed, and is consumed with the
same trust as the source tarball (fetched from the upstream GitHub release).

`gui` is amd64-only (the artifact is) and uses the non-vulkan variant,
matching the CLI's `vulkan` USE being off.

## Maintenance

The ebuild and fat Manifest are regenerated automatically by
`.github/workflows/bump.yml`: a daily cron (plus manual `workflow_dispatch`,
which defaults to a dry run) detects the newest upstream goose release and, if
it is not already packaged, regenerates the version-specific `CRATES` /
`GIT_CRATES` / crate `LICENSE+=` blocks with `pycargoebuild`, rebuilds the fat
Manifest, and commits + pushes to `main`. CI regenerates and publishes only -
it never compiles or emerges the package; the consumer builds via `emerge`.

- `scripts/bump.sh` - entry point. Also runs locally:
  `DRY_RUN=1 DISTDIR=/var/cache/distfiles bash scripts/bump.sh`
- `scripts/gen-manifest.py` - fat Manifest generator (crates.io + source +
  github `GIT_CRATES` archive tarball). Reproduces `pkgdev manifest` output
  byte-for-byte, so CI needs no portage/pkgcore.
- `scripts/license-mapping.conf` - pinned copy of Gentoo's license mapping for
  `pycargoebuild` (refresh from `metadata/license-mapping.conf` in the Gentoo
  tree if a bump reports an unmapped crate license).
- `Dockerfile` - pinned toolchain image used by the workflow.

## License note

`LICENSE` is the pycargoebuild-mapped union of crate licenses. Five non-chosen `OR`-branch tokens (`0BSD BSD-1 GPL-3 LGPL-2.1+ Apache-2.0-with-LLVM-exception`) are omitted per OR-branch semantics; there is no hard GPL dependency.
