# Sysupgrade image signing

Status: 2026-10-09, revised 2026-10-12. Implemented by openwrt 0004 (plus the
rpcd part of 0003) and luci 0003. Hardware verification is open.

## Goal

A device installs only firmware signed with the key of the tree it was built
from, held by whoever builds and ships that firmware. This is the install-time
authenticity and integrity check (EN 18031-1 SUM-2). It is not secure boot:
the check runs in the firmware (sysupgrade) when an image is installed, not
in the bootloader when the device starts.

## Mechanism (upstream, unchanged)

Build, `Build/append-metadata` in `include/image-commands.mk`:

    usign -S -m image -s $(BUILD_KEY) -x image.sig      # ed25519 over the image
    cp $(BUILD_KEY).ucert image.ucert
    ucert -A -c image.ucert -x image.sig                  # certificate + signature
    fwtool -S image.ucert image                           # appended as a trailer

Device, `fwtool_check_signature` in `/lib/upgrade/fwtool.sh`:

    fwtool -q -s /tmp/sysupgrade.ucert image              # extract the trailer
    fwtool -q -T -s /dev/null image | ucert -V -m - -c /tmp/sysupgrade.ucert -P /etc/opkg/keys

`ucert -V` walks the chain: the first certificate must be signed by a key in
`/etc/opkg/keys` (file name = usign fingerprint), each further one by the key
before it, the image signature by the last. Certificates carry `validfrom` /
`expiresat`, checked against the device clock (see Clock).

`REQUIRE_IMAGE_SIGNATURE=1` makes a missing or failing signature "invalid".
`sysupgrade -F` on the console can still flash; LuCI cannot (luci 0003). The
key directory survives a backup restore unchanged (openwrt 0004).

Signed: every `*-sysupgrade.bin`. Factory images are flashed by U-Boot and
are not checked here.

## What the overlay adds (openwrt 0004)

On an APK tree upstream never generated `key-build` / `key-build.ucert` nor
installed `/etc/opkg/keys`, so `SIGN_FIRMWARE=y` gave unsigned images and
nothing on the device verified. No upstream target sets
`REQUIRE_IMAGE_SIGNATURE`. The patch:

- generates the key pair and certificate on APK builds as the opkg branch
  does, at `$(TOPDIR)/key-build`;
- installs the build key's public half into `/etc/opkg/keys` under its
  fingerprint and pulls in `ucert` via `SIGN_FIRMWARE`;
- adds `CONFIG_REQUIRE_IMAGE_SIGNATURE` (default y, set in all configs):
  base-files ships `/lib/upgrade/signature.sh`, sourced after `platform.sh`,
  so it holds on every target. Off = upstream behaviour, so a developer image
  without keys keeps a working LuCI update path;
- makes `sysupgrade --restore-backup` put `/etc/opkg/keys` and
  `/etc/apk/keys` back as they were (`-F` skips this);
- teaches `ucert -I` the `-f <validfrom>` / `-e <expiresat>` options and
  issues `key-build.ucert` with them.

## Keys and trust

Upstream's model: the tree's `key-build` signs every image and is the only
key the image trusts. 8devices commits and ships no key; it belongs to
whoever runs the build (README "Keys": back it up, share between developer
checkouts if wanted, `BUILD_KEY=<path>` on a release host).

Not given: rotating or revoking without touching devices. `ucert -V`
supports a chain (root key in `/etc/opkg/keys` certifying a release key
carried in the image, `ucert -I -s <root>`), so that can be added later with
no device-side change beyond installing the root key. Today a key change is
one `sysupgrade -F` per device.

## Clock and certificate validity

`ucert -I` defaults to `validfrom` = now, `expiresat` = now + 365 days, and
`ucert -V` rejects outside that window (return 3). With
`REQUIRE_IMAGE_SIGNATURE=1`:

1. A device without RTC and NTP (LAN-only Lima, Carambola3) boots with the
   clock at the newest file under `/etc`, i.e. the build date of the firmware
   it runs. A certificate issued later looks "not yet valid".
2. A certificate reused past its first year makes every image carrying it
   unflashable on devices with a correct clock.

Policy (openwrt 0004): `key-build.ucert` is issued with `validfrom` =
2025-01-01 and `expiresat` = ten years from issue. The device check stays
strict; a wrong clock is an operational condition with the console `-F` path,
not a reason to skip verification. Re-issue (same key, new window): delete
`key-build.ucert` and rebuild, or
`ucert -I -c key-build.ucert -p key-build.pub -s key-build -f <epoch> -e <epoch>`.
Whoever ships images records the window for them (`ucert -D -c key-build.ucert`).

## Shipping images

For whoever builds and ships images from a release tag (8devices publishes
none):

    ./quick_start.sh kiwi-dvk -c                          # build host with its own key-build (or BUILD_KEY=<path>)
    staging_dir/host/bin/ucert -D -c key-build.ucert     # certificate validity window of these images

Before shipping: a device running the previous images must accept the new
image with plain `sysupgrade -T`.

## Threat model

Stops firmware not signed with a trusted key from being installed over the
network: tampered or wrong download, MITM on the transfer, an unsigned image
uploaded by mistake. luci 0003 removes the one-click "Force upgrade" in LuCI,
and a restored backup cannot change the trust keys (openwrt 0004). Adding a
trust key is a deliberate decision of the administrator (console, or the LuCI
keys page).

Does not confine the web administrator: LuCI runs as root and its stock pages
write `rc.local`, `/etc/crontabs/root` and `/etc/config/dropbear`, each a
root shell at next boot or login. The check protects against mistakes and
tampered images; anyone with the web password is root, so a stolen web
password is outside what it can stop. Acceptable for SUM-2 (the
administrator is the authorised party); do not describe the trust keys as
"not editable by the administrator".

Also outside: U-Boot TFTP recovery and factory images (bootloader path), and
a root shell on the serial console (physical access, out of scope).

## Verification on hardware (open)

Host-verified only: patches apply, shell syntax, ucert source read. The
checks to run on each board before release are in README.md, Device checks.
