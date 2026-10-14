# 8devices OpenWrt CRA/RED baseline

Upstream OpenWrt main pinned at 138fabb79f (2026-09-29), plus this directory,
the root `quick_start.sh` and the top section of the root `README.md`. No other
upstream file is changed in git. All 8devices changes are quilt patch series
and data files kept here; quick_start applies them to the working tree before
building (modifying upstream files there) and `make -C 8devices unapply`
restores the pristine tree, so a re-pin is a patch refresh, not a rebase.

Boards: Mango DVK (qualcommax/ipq60xx), Kiwi DVK (qualcommbe/ipq95xx), Lima
and Carambola3 (ath79/generic).

Why main and not 25.12: on Kiwi the release lacks the PPE EDMA RX fix
(ethernet link but no traffic), the SFP presence-detection backport and the
RTL8261N 10G firmware. main at this pin has ethernet, SFP, 10G, LuCI,
sysupgrade and all radios working on Kiwi. Cost: no point releases. Upstream
fixes CVEs on main, but this tree gets them only at the next re-pin; an urgent
fix before then is carried as a copy of the upstream commit in
`patches/backports/` (`docs/maintenance.md`). Plan: move to an OpenWrt release
branch once one carries what Kiwi needs; security fixes then arrive as its
point releases.

## Layout

    quick_start.sh          entry point (tree root): prepare + pick a config + optional build
    8devices/
      Makefile              apply / unapply / check (quilt), used by quick_start
      CHANGELOG.md          release notes, one section per release tag
      feeds.conf            feeds.conf.default with luci and packages pinned to a commit
      configs/              one diffconfig per board
      patches/backports/    upstream fixes carried between re-pins (CVE backports), applied first; normally empty
      patches/openwrt/      series + patches on the openwrt tree
      patches/luci/         series + patches on feeds/luci
      board-files/          Kiwi board-2.bin with the Noni id-12 profile + the vendor BDF it was built from
      scripts/
        make-kiwi-board.sh  rebuild the Kiwi board file and compare with the shipped one
        sbom-pedigree.py    called by image.mk (openwrt 0005): records the overlay patches in each image's SBOM
      docs/
        sysupgrade-signing.md  keys, certificates, threat model of the signed update path
        maintenance.md         re-pin, branches/tags/releases, CVE backports
      .pc/                  quilt state, per checkout, gitignored

While applied, the tree also has `feeds.conf` (ignored by upstream) and
`package/firmware/ipq-wifi/src/board-8devices_kiwi.qcn9274` (shows as
untracked; expected). `make -C 8devices unapply` removes both.

## Build

    ./quick_start.sh                  # menu of configs, then prepare + defconfig + key check
    ./quick_start.sh lima             # by name
    ./quick_start.sh lima -c          # and build right away
    ./quick_start.sh -l               # list configs
    make -j$(nproc)                   # after a quick_start without -c

quick_start runs `make -C 8devices apply` (openwrt series, Kiwi board file,
pinned feeds update, LuCI series, feeds install of luci/luci-ssl/sudo), copies
`configs/<name>.config` to `.config`, runs `make defconfig` and checks the
firmware signing key (see Keys). `-n` skips the feeds part, `-K <dir>` copies
a key in, `-d` prints the commands. Use `make menuconfig` only to deviate from
a predefined config. Images land in `bin/targets/<target>/<subtarget>/` with
the package manifest and the CycloneDX SBOM.

`make -C 8devices check` on an unapplied tree pushes every series, reports
`ok` or `FAIL` per series and pops them again.

Build-system notes on this pin: a change that only touches `files/` does not
retrigger the image step (`rm -f build_dir/target-*/linux-*/.image_install`
before rebuilding); on incremental builds the plain kernel can embed the
initramfs, so the configs keep `TARGET_ROOTFS_INITRAMFS` off; `VERSIONOPT`
needs `IMAGEOPT=y` or defconfig silently drops the version strings.

## Patches

Quilt format, one logical change each; the header of each patch describes the
change in full. Names carry the kind: `platform` = board support ahead of
upstream (goes away as things land upstream), `red` = RED / CRA (EN 18031)
compliance.

patches/openwrt
- 0001 platform: pin the Kiwi QCN9274 firmware to WLAN.WBE.1.4.1 (new package
  `ath12k-firmware-qcn9274-wbe141`); linux-firmware's 1.6 never starts the
  Noni cards on upstream ath12k.
- 0002 red: `admin` user with sudo, console always asks for login, root off
  the serial console, password dialog on the console while admin has none.
- 0003 red: SSH command whitelist (reboot/jffs2reset/firstboot), rpcd refuses
  login to an account without password, rpcd password policy (8 characters),
  HTTP redirects to HTTPS.
- 0004 red: signed and enforced sysupgrade images (APK key-generation fix,
  `REQUIRE_IMAGE_SIGNATURE`, backup restore cannot change trust keys, ucert
  validity options). See `docs/sysupgrade-signing.md`.
- 0005 red: record the overlay patches in each image's CycloneDX SBOM via
  `scripts/sbom-pedigree.py`.

patches/luci
- 0001 platform: limit band and channel lists to the configured sub-radio
  (Kiwi: one phy, a 2.4 GHz and a 5/6 GHz sub-radio).
- 0002 red: initial root password page while root has none, password policy
  enforced server-side in `luci setPassword`.
- 0003 red: no forced sysupgrade from the web UI.

board-files (data, not a patch)
- `board-8devices_kiwi.qcn9274`: upstream qca-wireless file plus the Noni
  wideband board image (id 12). Provenance and rebuild:
  `board-files/8devices_kiwi/README.md`.

SBOM: `sbom-pedigree.py` adds a `pedigree.patches` list to every component
whose source a patch touches (e.g. base-files, rpcd, ucert, luci-base),
records patches that touch no package (openwrt 0005, `include/image.mk`) on
`metadata.component`, the image, and adds a note with the installed file's
md5 to `ipq-wifi-8devices_kiwi` for the board file.

Not ported from RED (obsolete or replaced): kernel 6.6 bumps, x86 mitigation,
openssl LICENSE fix (upstream), shipped root/admin password hashes, the
committed signing key, unconditional signing, RED's feeds forks, RED.md, full
per-board defconfigs, the rbash jail.

## Default security configuration of an image

- First use: the serial console shows a "set a password for admin" dialog
  until admin has one (8+ characters); LuCI shows a "set the administrator
  password" page until root has one. Neither account can log in anywhere
  while it has no password (rpcd refuses, dropbear refuses blank passwords,
  the console dialog comes before the login prompt).
- Login: serial console asks for login; root refused on serial; log in as
  `admin`, `sudo -i`. Web: root, over HTTPS (self-signed certificate from
  px5g; HTTP redirects). Password policy: 8+ characters, enforced for LuCI and
  ubus setPassword and for the console dialog; busybox `passwd` on a root
  shell is not.
- SSH: command whitelist, only reboot / jffs2reset / firstboot, for every
  user including root; no shell, no scp/sftp. Dev image: drop the
  ForceCommand from /etc/config/dropbear or the uci-default.
- Updates: sysupgrade images are usign-signed and the device only accepts
  images signed with a key it trusts (EN 18031-1 SUM-2); LuCI cannot force
  an unsigned image, and a backup restore cannot change the trust keys. LuCI is the network update path and is in every config:
  the SSH whitelist allows no sysupgrade. Also: `SIGNED_PACKAGES`,
  `DOWNLOAD_CHECK_CERTIFICATE`, CycloneDX SBOM per image.
- No boot-time verification: the kernel is not signed, images boot on stock
  bootloaders.
- Threat model: the web administrator is a fully privileged role (LuCI runs
  as root). The controls above bind parties without administrator
  credentials and protect against tampered images and mistakes; they do not
  confine a hostile administrator. Details: `docs/sysupgrade-signing.md`.

Not covered (EN 18031-1 items RED never had, scope to decide): brute-force
limiting in dropbear/uhttpd/rpcd, a default country for Kiwi 6 GHz radios.

## Keys

The firmware signing key is upstream's usign pair in the tree root:
`key-build` (private) and `key-build.pub` (public), an ed25519 key pair in
signify format. It is required: every image is signed with it, and a
device accepts only images signed with the key it was flashed with.
8devices commits and ships no key; whoever builds owns it.

- The first build generates it if missing. quick_start reports whether it is
  present (with its fingerprint once usign is built) on every run.
- Back up both files. Never commit or share `key-build`; upstream's
  `.gitignore` already excludes `key-build*`.
- Existing key: `./quick_start.sh <board> -K <dir>` copies `key-build` and
  `key-build.pub` from `<dir>` into the tree root. Release hosts can also use
  `make BUILD_KEY=<path>` (upstream option).
- By hand: `staging_dir/host/bin/usign -G -s key-build -p key-build.pub`
  (after any build), or OpenBSD `signify -G -n -s key-build -p key-build.pub`
  (`-n`: no passphrase, the build cannot use an encrypted key).
- Changing the key on a device: `sysupgrade -F` on the console once, or
  U-Boot TFTP recovery (which never checks the signature). Several developers
  flashing the same boards copy the two files between checkouts.

Generated by the build next to the key, not firmware keys: `key-build.ucert`,
the certificate carried in each image (re-issued when missing, valid from
2025-01-01 until ten years after the build that issued it), and
`private-key.pem` / `public-key.pem`, the OpenSSL pair that signs the APK
package index (only matters if devices install packages from this build).

## Device checks

    ubus call system board | grep rootfs_type         # squashfs
    dmesg | grep -E "fw_build_id|failed to fetch board" # Kiwi: 3x 1.4.1, no fetch failures
    iw phy | grep -c Wiphy                             # Kiwi: 3 (SoM + 2 Nonis)
    # fresh device: serial shows the admin password dialog, http://dev redirects to https and shows the root password page
    ubus call session login '{"username":"root","password":""}'   # before a password is set: Access denied (also over /ubus)
    ssh admin@dev ash                                  # refused; ssh admin@dev reboot works; ssh admin@dev 'echo $(</etc/passwd)' refused
    ubus call luci setPassword '{"username":"root","password":"short"}'   # result false
    sysupgrade -T <unsigned.bin>                       # refused, "Image signature not present"
    sysupgrade -T <signed-other-key.bin>               # refused
    sysupgrade -T <signed.bin>                         # ok
    sysupgrade -T <signed.bin with 1 byte changed in the rootfs>   # refused
    date -s 2024-01-01; sysupgrade -T <signed.bin>     # refused (clock), -F ok
    sysupgrade -r <backup containing etc/opkg/keys/x> && ls /etc/opkg/keys   # unchanged
    # LuCI: flash signed -> ok; "Force upgrade" with unsigned -> rpcd refuses
    # build with CONFIG_REQUIRE_IMAGE_SIGNATURE=n: unsigned image flashes from LuCI
    #   (development only: such an image is NOT CRA compliant, never ship it)

Kiwi Wi-Fi needs a correct country and encryption on every radio, or 5/6 GHz
does not come up: the generated config has country `00` on 6 GHz, which the
firmware rejects, so set the real country; 6 GHz needs WPA3 (`sae`), 2.4/5
GHz work with WPA2/WPA3 mixed (`sae-mixed`). Flash: `factory.bin` as
`fwupdate.bin` on TFTP, `run do_recovery` in U-Boot; sysupgrade.bin for the
running system.

LuCI JS is cached by the browser across reflashes from the same pin
(identical mtimes): hard-reload before judging a LuCI change.

## Status and known limitations

Verified on Kiwi DVK with two Nonis (2026-10-01): ethernet, SFP, 10G, LuCI,
sysupgrade, all four APs (Noni id 12 wideband, Noni id 4, SoM 2.4 GHz, SoM
5/6 GHz), the LuCI sub-radio patch, the pinned firmware package and the board
file in the image and SBOM. Not yet flashed (host-verified only: patches apply,
shell syntax, dry runs): openwrt 0002, 0003, 0004 and luci 0002. Mango DVK,
Lima and Carambola3: configs pass `make defconfig`, nothing built or flashed
yet.

- Kiwi Wi-Fi firmware pinned to 1.4.1 until a public 1.6 build works on Nonis.
- Noni split profile (0x1006) untested; wideband needs the id-12 entry.
- Kiwi SoM 5 GHz: DFS channels (52-144) do not start ("invalid regdomain",
  firmware never confirms the country); use 36-48 or 149-165.
- LuCI cannot set the transmit power of a radio on a 6 GHz channel (both Kiwi
  Nonis): the list stays empty (upstream libiwinfo). Set
  `wireless.radioN.txpower` with uci.
- Kiwi U-Boot recovery and upstream sysupgrade write slot A only; a board
  booting slot B cannot be upgraded (ipq807x has /proc/cmdline detection).
- The SSH ForceCommand is set once at first boot; a hand-edited
  /etc/config/dropbear (or the LuCI SSH page, which has uci write on dropbear)
  can remove it. Web administrator = root, see Threat model.
- The LuCI initial-password form is unauthenticated by nature (there is no
  credential yet) and has no CSRF token: whoever reaches a fresh device first
  sets its password, as with any first-boot flow without per-device secrets.
- The HTTPS certificate is self-signed; browsers warn until it is replaced.
- No point releases on a main pin.
