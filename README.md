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

## Maintenance

The ebuild and fat Manifest are regenerated per upstream version with `pycargoebuild` (CRATES) and `pkgdev manifest` (digests). Automatic version detection + bump (CI) is planned.

## License note

`LICENSE` is the pycargoebuild-mapped union of crate licenses. Five non-chosen `OR`-branch tokens (`0BSD BSD-1 GPL-3 LGPL-2.1+ Apache-2.0-with-LLVM-exception`) are omitted per OR-branch semantics; there is no hard GPL dependency.
