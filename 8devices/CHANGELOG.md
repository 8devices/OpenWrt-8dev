# Changelog

One section per release tag (see `docs/maintenance.md`, tags). Each section is
the release notes: upstream and feed pins, boards, changes, fixed
vulnerabilities, device checks run.

## main-138fabb79f-cra (unreleased)

Upstream: OpenWrt main 138fabb79f (2026-09-29).
Feeds: packages 95d73ebcc9, luci 07bca003c7 (`feeds.conf`).
Boards: kiwi-dvk, mango-dvk, lima, carambola3.

- First CRA/RED baseline (see README "Patches"): admin account with sudo and
  console login, root off the serial console, initial passwords on console and
  LuCI, SSH command whitelist, rpcd password policy, HTTPS, signed and enforced
  sysupgrade images, overlay patches recorded in the SBOM.
- Kiwi: QCN9274 firmware pinned to WLAN.WBE.1.4.1, LuCI band lists limited to
  the sub-radio, board file with the Noni wideband profile.
- Fixed vulnerabilities: none (first release).
- Device checks run: to be filled at release.
