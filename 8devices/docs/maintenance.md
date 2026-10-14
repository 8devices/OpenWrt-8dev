# Maintenance: re-pin, branches and releases, CVE backports

## Working on a patch

When you need it: `make -C 8devices apply` stops at a patch that no longer
fits the tree (usually after a re-pin). The patches before it are applied,
that one and the rest are not. You fix that one patch by hand with quilt, then
run `make -C 8devices apply` again and it continues.

Run the commands in the tree root for the `openwrt` and `backports` series, in
`feeds/luci` for the `luci` series:

    S=openwrt                                    # series: openwrt | backports | luci
    O=/path/to/tree/8devices                     # absolute path to this directory
    export QUILT_PATCHES=$O/patches/$S QUILT_PC=$O/.pc/patches/$S
    quilt push -f                                # apply the failing patch, misfits go to *.rej
    # fix the files by hand, delete the .rej files
    quilt refresh -p ab --no-timestamps --no-index
    make -C $O apply                             # continue with the next patch

- `QUILT_PATCHES` is where the patch files and their `series` list are;
  `QUILT_PC` is where quilt records which patches are applied. Both point
  into this directory so manual quilt and `make apply` share the same state.
  Without them quilt looks for `patches/` and `.pc/` in the current
  directory and finds no series.
- `quilt push -f` applies the next patch by force: the parts that fit are
  applied, the parts that do not are saved next to the files as `*.rej`.
  Each `.rej` shows what the patch wanted to change; make that change in the
  real file, then delete the `.rej`.
- `quilt refresh` writes the fixed state back into the patch file in
  `patches/<series>/`, keeping its header. The flags keep the style of the
  existing patches (`a/` `b/` paths, no timestamps, no `index` lines);
  without them the refreshed patch comes out in a different format.

New patch: after `make -C 8devices apply` and the `export` line above,
`quilt new NNNN-<name>.patch`, then `quilt add <file>` for every file before
you edit it, edit, and `quilt refresh` with the flags above. quilt adds the
new patch to `series`. Then write the header (what and why) at the top of the
patch file.

## Re-pin to a newer upstream

    make -C 8devices unapply
    git fetch upstream
    git checkout -b main-<new-sha>-cra-red <new-sha>
    git cherry-pick <overlay commits of the previous pin branch>   # they only add files
    make -C 8devices apply          # quilt stops at the first patch that does not apply
    # fix it (Working on a patch), then run make -C 8devices apply again; repeat
    make -C 8devices unapply && make -C 8devices check   # every series: ok

Then update the pin (hash and date) in the root `README.md` and the first line
of `8devices/README.md`, drop backports the new pin already contains (see
below), build every board and run the Device checks.

## Repository, branches, tags and releases

One repository, `github.com/8devices/OpenWrt-8dev`: the full upstream OpenWrt
tree plus this overlay, so a clone is buildable without submodules or fetch
scripts, and the overlay is always next to the exact upstream commit it was
written for. Remote `upstream` = `github.com/openwrt/openwrt`.

Branches:

- `main-<upstream-sha>-cra-red`: one branch per upstream pin, e.g.
  `main-138fabb79f-cra-red`. Its history is upstream up to the pin, then
  commits that touch only `8devices/`, `quick_start.sh` and `README.md`.
  Invariant, check before every tag:

      git diff --stat <upstream-sha>..HEAD -- . ':!8devices' ':!quick_start.sh' ':!README.md'   # must be empty

- A re-pin is a new branch from the new upstream commit with the overlay
  commits cherry-picked on top. The old branch stays for history only; it
  gets no fixes. Devices on an older release get fixes by updating to the
  newest one.

Tags name the upstream base plus `-cra`, on the commit that was built:

    main-138fabb79f-cra          main pin
    v25.12.6-cra                 OpenWrt release tag, once on a release branch

Cadence: a release follows every OpenWrt release (once on a release branch,
every point release such as v25.12.6), and at least one every six months.

A release = the tag + its section in `8devices/CHANGELOG.md`: upstream pin,
feed pins (`8devices/feeds.conf`), the patch list of every series, the
backports with CVE ids, and the Device checks run per board. No images are
published: whoever builds from the tag (`./quick_start.sh <board> -c`) gets
the images, manifest and SBOM in `bin/targets/`, signed with their own key.

## Security fixes between re-pins

A main pin gets no point releases, so an upstream fix needed before the next
re-pin is carried as a patch in `patches/backports/`. That series is applied
before the openwrt series, lands in every image's SBOM through the pedigree
(openwrt 0005), and empties again at the next re-pin. Never `git cherry-pick`
into the tree: it breaks the branch invariant above and hides the fix from
the SBOM.

1. Sources, checked at least monthly and before every release:
   `https://app.opencve.io/cve/?vendor=openwrt`, the OpenWrt security
   advisories, `git log upstream/main --grep=CVE-` after `git fetch upstream`,
   and the same on the feeds (`git -C feeds/luci log origin/master --grep=CVE-`,
   likewise `feeds/packages`). Kernel CVEs: the stable tree of the kernel
   version in `include/kernel-6.x`.
2. Affected? The package must be in a shipped image: grep the board's
   `*.manifest` / `*.bom.cdx.json` in `bin/targets/` for the package and
   version. Build-host-only tools and packages not in any config are noted
   and skipped.
3. Find the fix. Usually an upstream OpenWrt commit (package bump, or a new
   file under `target/linux/generic/backport-6.x/` for the kernel). If upstream
   has not fixed it yet, write the patch as upstream would (same directories),
   and submit it upstream in parallel.
4. Carry it:

       git fetch upstream
       git format-patch -1 <sha> --stdout > 8devices/patches/backports/NNNN-CVE-YYYY-XXXX-<package>.patch
       echo NNNN-CVE-YYYY-XXXX-<package>.patch >> 8devices/patches/backports/series
       make -C 8devices unapply && make -C 8devices check    # every series: ok
       ./quick_start.sh <board> -c                            # each affected board

   A hand-written fix instead: `make -C 8devices apply`, then `quilt new` in
   the backports series (Working on a patch). NNNN continues the series
   numbering. The patch header must name the CVE, the upstream commit and the
   affected packages and boards; the release notes and the SBOM pedigree
   point at it.
5. Feed packages (luci, packages): prefer moving the feed pin in
   `8devices/feeds.conf` to the upstream commit containing the fix, after
   reading `git -C feeds/<feed> log --oneline <old>..<new>` for unrelated
   changes; `make -C 8devices apply` updates the feeds and re-applies the
   LuCI series on the new pin. If the pin move drags in too much, carry the
   fix like the LuCI series does (a `patches/packages/` series would need its
   own lines in the Makefile; not set up today).
6. Run the Device checks for the affected area, update Status in
   `8devices/README.md`; it ships with the next release, or earlier if it
   cannot wait (tag scheme for that to be decided when first needed).
7. At the next re-pin, drop every backport the new upstream commit already
   contains (`git log <new-pin> --grep=<CVE>`, or the patch fails to apply);
   the series should end up empty again.
