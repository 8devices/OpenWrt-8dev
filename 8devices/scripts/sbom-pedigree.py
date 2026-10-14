#!/usr/bin/env python3
"""Annotate an OpenWrt CycloneDX SBOM with the 8devices overlay patches.

The SBOM that include/image.mk generates lists every package with its
upstream version. The 8devices overlay changes some of those packages with
quilt series applied onto the tree before the build (make -C 8devices apply), which the version cannot show. This
script adds a CycloneDX "pedigree" to each component the overlay patches,
listing the patches (type "unofficial", diff.url = patch path relative to
the source tree). Patches that touch no package (build system, tools,
image recipes) are recorded on metadata.component, the firmware image. Data
files the overlay installs (the Kiwi board file) get a pedigree note on their
package with the md5 of the installed file.

Usage: sbom-pedigree.py --overlay <dir> --packageinfo <file> <bom.cdx.json>

Which patches count: for each <overlay>/patches/<target>/series the list
of applied patches from <overlay>/.pc/patches/<target>/applied-patches, or the
whole series when quilt state is missing. <target> backports (upstream fixes
carried between re-pins) and openwrt are the tree root, luci is feeds/luci.
Re-running replaces earlier annotations.
"""
import argparse
import hashlib
import json
import os
import sys

NOTE = "8devices overlay"
TARGET_PREFIX = {"backports": "", "openwrt": "", "luci": "feeds/luci/"}


def applied_patches(overlay, series_dir):
    """Patches of one series, in order: quilt's applied list, else the series file."""
    rel = os.path.relpath(series_dir, overlay)
    pc = os.path.join(overlay, ".pc", rel, "applied-patches")
    src = pc if os.path.isfile(pc) else os.path.join(series_dir, "series")
    if src != pc:
        print(f"sbom-pedigree: no quilt state for {rel}, assuming the whole series is applied", file=sys.stderr)
    with open(src) as f:
        return [l.split()[0] for l in f if l.strip() and not l.startswith("#")]


def patched_paths(patch_file, prefix):
    """Tree-relative paths a patch touches, from its +++ lines."""
    paths = []
    with open(patch_file, errors="replace") as f:
        for line in f:
            if line.startswith("+++ "):
                p = line[4:].split("\t")[0].strip()
                if p == "/dev/null":
                    continue
                if p.startswith("b/"):
                    p = p[2:]
                paths.append(prefix + p)
    return paths


def source_dirs(packageinfo, tree):
    """Map package source directory -> binary package names, from .packageinfo.

    Feed packages are listed through their package/feeds/<feed>/<name> symlink;
    both that path and the real feeds/<feed>/... path are registered so the
    +++ paths of a feed patch (prefixed with feeds/<feed>/) find their owner.
    """
    dirs = {}
    srcdirs = ()
    with open(packageinfo, errors="replace") as f:
        for line in f:
            if line.startswith("Source-Makefile:"):
                srcdir = os.path.dirname(line.split(":", 1)[1].strip())
                srcdirs = {srcdir}
                real = os.path.relpath(os.path.realpath(os.path.join(tree, srcdir)), tree)
                if not real.startswith(".."):
                    srcdirs.add(real)
            elif line.startswith("Package:") and srcdirs:
                for d in srcdirs:
                    dirs.setdefault(d, set()).add(line.split(":", 1)[1].strip())
    return dirs


def owner(path, dirs):
    """The package source directory that contains path, or None."""
    p = path
    while p:
        if p in dirs:
            return p
        p = os.path.dirname(p)
    return None


# Data files the overlay installs into the tree (not patches): binary package
# name -> (installed path, overlay source, what it is). The component keeps the
# upstream version; the pedigree note says what differs.
DATA_FILES = {
    "ipq-wifi-8devices_kiwi": (
        "package/firmware/ipq-wifi/src/board-8devices_kiwi.qcn9274",
        "8devices/board-files/8devices_kiwi/board-8devices_kiwi.qcn9274",
        "board-2.bin is the upstream qca-wireless container plus one board image "
        "(bus=pci,qmi-chip-id=0,qmi-board-id=12, payload bdwlan.b000c, Noni wideband)",
    ),
}


def data_file_note(tree, pkg):
    """Pedigree note for an overlay data file, or None when it is not installed."""
    installed, source, what = DATA_FILES[pkg]
    path = os.path.join(tree, installed)
    if not os.path.isfile(path):
        return None
    with open(path, "rb") as f:
        md5 = hashlib.md5(f.read()).hexdigest()
    return (f"{NOTE}: {what}; installed from {source} before the build, "
            f"md5 {md5}; see 8devices/board-files/8devices_kiwi/README.md.")


def pedigree(patches, what):
    return {
        "notes": f"{NOTE}: {what} is upstream plus {len(patches)} patch(es) applied onto the tree before the "
                 "build; diff.url is the patch path relative to the source tree.",
        "patches": [{"type": "unofficial", "diff": {"url": p}} for p in patches],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--overlay", required=True)
    ap.add_argument("--packageinfo", required=True)
    ap.add_argument("bom")
    a = ap.parse_args()
    overlay = os.path.abspath(a.overlay)
    tree = os.path.dirname(overlay)

    dirs = source_dirs(a.packageinfo, tree)
    by_pkg = {}      # binary package name -> [patch paths]
    tree_level = []  # patches touching no package
    for target, prefix in TARGET_PREFIX.items():
        sdir = os.path.join(overlay, "patches", target)
        if not os.path.isfile(os.path.join(sdir, "series")):
            continue
        for name in applied_patches(overlay, sdir):
            pfile = os.path.join(sdir, name)
            url = os.path.relpath(pfile, tree)
            owners = {owner(p, dirs) for p in patched_paths(pfile, prefix)}
            owners.discard(None)
            if not owners:
                tree_level.append(url)
            for d in owners:
                for pkg in dirs[d]:
                    by_pkg.setdefault(pkg, []).append(url)

    with open(a.bom) as f:
        bom = json.load(f)

    for c in bom.get("components", []):
        if c.get("pedigree", {}).get("notes", "").startswith(NOTE):
            del c["pedigree"]
    annotated = []
    for c in bom.get("components", []):
        if c["name"] in by_pkg:
            c["pedigree"] = pedigree(by_pkg[c["name"]], c["name"])
            annotated.append(c["name"])
        elif c["name"] in DATA_FILES:
            note = data_file_note(tree, c["name"])
            if note:
                c["pedigree"] = {"notes": note}
                annotated.append(c["name"])

    meta = bom.setdefault("metadata", {})
    comp = meta.get("component")
    if comp and comp.get("pedigree", {}).get("notes", "").startswith(NOTE):
        del comp["pedigree"]
    if tree_level:
        if not comp:
            name = os.path.basename(a.bom)
            for suffix in (".bom.cdx.json", ".cdx.json", ".json"):
                if name.endswith(suffix):
                    name = name[: -len(suffix)]
                    break
            comp = meta["component"] = {"type": "firmware", "name": name}
        comp["pedigree"] = pedigree(tree_level, "the firmware image build")

    with open(a.bom, "w") as f:
        f.write(json.dumps(bom, sort_keys=True, separators=(",", ":")))
    print(f"sbom-pedigree: annotated {len(annotated)} component(s) "
          f"({', '.join(sorted(annotated))}) and {len(tree_level)} tree-level patch(es)")


if __name__ == "__main__":
    main()
