# Toolchain for scripts/bump.sh: regenerates the dev-util/goose ebuild + fat
# Manifest and publishes them. It never compiles or emerges the package - the
# consumer builds via `emerge`.
#
# Base pinned by digest; tool versions pinned below.

FROM python:3.13-slim@sha256:b3575dcf816cdacc5292df77a6e3e59b8941631078373a045efa2ac1e9c5c3b2

# ca-certificates + curl: source tarball + GitHub API; git: commit + push;
# wget: pycargoebuild's crate fetcher (its documented fallback fetcher);
# xz-utils: .tar.xz handling.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		git \
		wget \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*

# GitHub CLI, pinned and checksum-verified. Used for upstream tag detection.
ARG GH_VERSION=2.103.3
ARG GH_SHA256=4c806978ffce1cec70853302a56d70ac6da4f19bae7adca4e1a8ab00633dd91d
RUN curl -fsSL -o /tmp/gh.tar.gz \
		"https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
	&& echo "${GH_SHA256}  /tmp/gh.tar.gz" | sha256sum -c - \
	&& tar -xzf /tmp/gh.tar.gz -C /tmp \
	&& install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
	&& rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_amd64"

# pycargoebuild refreshes the CRATES, GIT_CRATES and crate LICENSE+= blocks of
# the seeded ebuild in place. pkgdev is included for parity with a local Gentoo
# workflow but is NOT on the critical path: `pkgdev manifest` needs a pkgcore
# domain, which this slim image does not provide. scripts/gen-manifest.py
# replaces it and is proven to reproduce dev-util/goose's pkgdev Manifest
# byte-for-byte.
RUN pip install --no-cache-dir \
		pycargoebuild==0.17.2 \
		pkgdev==0.2.19

WORKDIR /repo
