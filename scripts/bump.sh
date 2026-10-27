#!/usr/bin/env bash
# Regenerate the dev-util/goose ebuild + fat Manifest for a new upstream release.
#
# Local dry run:  DRY_RUN=1 DISTDIR=/var/cache/distfiles bash scripts/bump.sh
# CI:             TARGET_TAG / DRY_RUN / GH_TOKEN / DISTDIR come from
#                 .github/workflows/bump.yml
#
# Detects the newest upstream goose tag; if its ebuild is already present the
# run is a no-op. Otherwise it seeds a new ebuild from the current one,
# refreshes the version-specific blocks with pycargoebuild, regenerates the
# fat Manifest, and (unless DRY_RUN) commits and pushes. No compilation and no
# emerge happen here - the consumer builds via `emerge`.
set -euo pipefail

cd "$(dirname "$0")/.."

UPSTREAM="aaif-goose/goose"
PKG_DIR="dev-util/goose"
LICENSE_MAPPING="scripts/license-mapping.conf"
DISTDIR="${DISTDIR:-${PWD}/distfiles}"

detect_tag() {
	local t
	if command -v gh >/dev/null 2>&1 &&
		t="$(gh api "repos/${UPSTREAM}/releases/latest" --jq .tag_name 2>/dev/null)"; then
		printf '%s\n' "${t}"
		return 0
	fi
	curl -fsSL -H "Accept: application/vnd.github+json" \
		"https://api.github.com/repos/${UPSTREAM}/releases/latest" |
		python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])'
}

tag="${1:-${TARGET_TAG:-}}"
if [[ -z ${tag} ]]; then
	tag="$(detect_tag)"
fi
pv="${tag#v}"
# SRC_URI in the ebuild is https://github.com/${UPSTREAM}/archive/v${PV}.tar.gz
[[ ${tag} == "v${pv}" ]] || { echo "unexpected upstream tag format: ${tag}" >&2; exit 1; }

local_latest="$(ls "${PKG_DIR}"/goose-*.ebuild 2>/dev/null |
	sed -E 's|.*/goose-(.*)\.ebuild$|\1|' | sort -V | tail -n1)"
[[ -n ${local_latest} ]] || { echo "no existing goose ebuild to seed from" >&2; exit 1; }

if [[ ${pv} == "${local_latest}" && ${FORCE:-0} != 1 ]]; then
	echo "up to date: goose-${pv} ebuild already present"
	exit 0
fi
if [[ -e "${PKG_DIR}/goose-${pv}.ebuild" && ${FORCE:-0} != 1 ]]; then
	echo "goose-${pv}.ebuild already present"
	exit 0
fi
if [[ $(printf '%s\n%s\n' "${local_latest}" "${pv}" | sort -V | tail -n1) != "${pv}" ]]; then
	echo "refusing to downgrade goose ${local_latest} -> ${pv}" >&2
	exit 1
fi

mkdir -p "${DISTDIR}"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# 1. upstream source archive - the exact distfile the ebuild declares
src_file="${DISTDIR}/goose-${pv}.tar.gz"
if [[ ! -f ${src_file} ]]; then
	echo "fetching https://github.com/${UPSTREAM}/archive/${tag}.tar.gz"
	curl -fL --retry 3 --retry-delay 5 -o "${src_file}.part" \
		"https://github.com/${UPSTREAM}/archive/${tag}.tar.gz"
	mv "${src_file}.part" "${src_file}"
fi

# 2. extract it (pycargoebuild runs in a workspace member, not the root)
tar xzf "${src_file}" -C "${work}"
srcdir="${work}/goose-${pv}"
[[ -f ${srcdir}/Cargo.lock ]] || { echo "no Cargo.lock under ${srcdir}" >&2; exit 1; }

# 3. seed the new ebuild from the previous one, then refresh the
#    version-specific CRATES / GIT_CRATES / crate LICENSE+= blocks in place.
#    pycargoebuild fetches the crates into DISTDIR itself.
prev_ebuild="${PKG_DIR}/goose-${local_latest}.ebuild"
new_ebuild="${PKG_DIR}/goose-${pv}.ebuild"
if [[ ${prev_ebuild} != "${new_ebuild}" ]]; then
	cp "${prev_ebuild}" "${new_ebuild}"
fi
pycargoebuild -C -i "${new_ebuild}" \
	-d "${DISTDIR}" \
	-l "${LICENSE_MAPPING}" \
	-M \
	"${srcdir}/crates/goose-cli"

# 4. fat Manifest: 1135 crates + source tarball + git crate
python3 scripts/gen-manifest.py "${new_ebuild}" "${DISTDIR}" "${PKG_DIR}/Manifest"

if [[ ${DRY_RUN:-1} == 1 ]]; then
	echo "DRY RUN: changes staged, nothing committed"
	git status --short
	git --no-pager diff -- "${PKG_DIR}"
	exit 0
fi

# 5. publish. CI runners have no default git identity.
if [[ -n ${GITHUB_ACTIONS:-} ]]; then
	git config user.name "github-actions[bot]"
	git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
fi
git add "${PKG_DIR}"
git commit -m "dev-util/goose ${pv}: ebuild + Manifest"
git push
