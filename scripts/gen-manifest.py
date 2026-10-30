#!/usr/bin/env python3
"""Regenerate the FAT Gentoo Manifest for a cargo.eclass ebuild.

Usage: gen-manifest.py <ebuild> <distdir> <manifest-path>

Derives the distfile set from the ebuild itself: the CRATES list (crates.io),
the source tarball declared in SRC_URI, and any github GIT_CRATES entry
(github archive tarball, matching cargo.eclass). Files already present in
<distdir> are reused; only missing ones are downloaded.

stdlib only: no portage, no pkgdev, no pkgcore. This reproduces `pkgdev
manifest` output byte-for-byte for dev-util/goose (verified against the
1.56.0 Manifest), which is why it can run in a slim CI image where pkgdev
manifest cannot (it needs a pkgcore domain).
"""

import hashlib
import os
import re
import sys
import urllib.request
from collections import OrderedDict

CHUNK = 1 << 20


def parse_ebuild_name(path):
    base = os.path.basename(path)
    stem = re.sub(r"\.ebuild$", "", base)
    m = re.match(r"^(?P<pn>.+)-(?P<pv>[0-9][^-]*(?:-r[0-9]+)?)$", stem)
    if not m:
        sys.exit("cannot split PN/PV from ebuild name: %r" % stem)
    pn = m.group("pn")
    pv = m.group("pv")
    return {"PN": pn, "PV": pv, "P": "%s-%s" % (pn, pv)}


def expand_vars(text, var):
    out = text
    for key in ("PN", "PV", "P"):
        out = out.replace("${%s}" % key, var[key])
        out = out.replace("$%s" % key, var[key])
    return out


def parse_crates(text):
    m = re.search(r'^CRATES="(.*?)"\s*$', text, re.M | re.S)
    if not m:
        sys.exit("no CRATES=... block found")
    return [line.strip() for line in m.group(1).splitlines() if line.strip()]


def parse_git_crates(text):
    m = re.search(r"declare\s+-A\s+GIT_CRATES=\((.*?)\)", text, re.S)
    if not m:
        return {}
    result = {}
    # cargo.eclass format: uri;commit[;crate_dir][;host]; pycargoebuild may
    # emit single-quoted values with a trailing ;name-%commit% field.
    for name, value in re.findall(r"""\[([^\]]+)\]=["']([^"']+)["']""", m.group(1)):
        fields = value.split(";")
        result[name] = (fields[0], fields[1])
    return result


def git_crate_distfile(url, commit):
    if "github.com" not in url:
        sys.exit("unsupported git host (only github handled): %s" % url)
    repo_name = url.rstrip("/").rsplit("/", 1)[-1]
    filename = "%s-%s.gh.tar.gz" % (repo_name, commit)
    dl_url = "%s/archive/%s.tar.gz" % (url.rstrip("/"), commit)
    return filename, dl_url


def parse_src_uri(text, var):
    # The SRC_URI block spans lines; the closing quote sits alone on a line.
    # Scan for that line rather than matching to the first quote. Conditional
    # entries use the gui? ( ... ) dep-string form, so the only URL lines are
    # the plain "url -> name" pairs (the gui? / ) lines carry no ->).
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.startswith('SRC_URI="'):
            start = i
            break
    if start is None:
        sys.exit("no SRC_URI=... block found")
    end = None
    for j in range(start + 1, len(lines)):
        if lines[j].rstrip() == '"':
            end = j
            break
    if end is None:
        sys.exit("unterminated SRC_URI block")
    block = "\n".join(lines[start + 1:end])
    files = OrderedDict()
    for url, rename in re.findall(r"(\S+)\s*->\s*(\S+)", block):
        files[expand_vars(rename, var)] = expand_vars(url, var)
    return files


def build_file_map(ebuild_path):
    with open(ebuild_path, "r", encoding="utf-8") as fh:
        text = fh.read()
    var = parse_ebuild_name(ebuild_path)

    files = OrderedDict()
    files.update(parse_src_uri(text, var))

    for entry in parse_crates(text):
        name, version = entry.split("@", 1)
        filename = "%s-%s.crate" % (name, version)
        files[filename] = (
            "https://static.crates.io/crates/%s/%s-%s.crate" % (name, name, version)
        )

    for _name, (url, commit) in parse_git_crates(text).items():
        filename, dl_url = git_crate_distfile(url, commit)
        files[filename] = dl_url

    return files


def digest(path):
    blake = hashlib.blake2b(digest_size=64)
    sha = hashlib.sha512()
    size = 0
    with open(path, "rb") as fh:
        while True:
            block = fh.read(CHUNK)
            if not block:
                break
            size += len(block)
            blake.update(block)
            sha.update(block)
    return size, blake.hexdigest(), sha.hexdigest()


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: %s <ebuild> <distdir> <manifest-path>" % sys.argv[0])
    ebuild, distdir, manifest_path = sys.argv[1:4]

    files = build_file_map(ebuild)

    cached = downloaded = 0
    lines = []
    for filename in sorted(files):
        path = os.path.join(distdir, filename)
        if os.path.exists(path):
            cached += 1
        else:
            downloaded += 1
            tmp = path + ".part"
            urllib.request.urlretrieve(files[filename], tmp)
            os.replace(tmp, path)
        size, blake, sha = digest(path)
        lines.append("DIST %s %d BLAKE2B %s SHA512 %s" % (filename, size, blake, sha))

    with open(manifest_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    print("ebuild:          %s" % ebuild)
    print("distdir:         %s" % distdir)
    print("manifest:        %s" % manifest_path)
    print("distfiles total: %d" % len(files))
    print("from cache:      %d" % cached)
    print("downloaded:      %d" % downloaded)


if __name__ == "__main__":
    main()
