# 8devices Kiwi QCN9274 board file (board-2.bin)

`board-8devices_kiwi.qcn9274` is installed by the OpenWrt package
`ipq-wifi-8devices_kiwi` as `/lib/firmware/ath12k/QCN9274/hw2.0/board-2.bin`
(copied into `package/firmware/ipq-wifi/src/` by `make -C 8devices apply`;
`include/package-defaults.mk` copies `src/` over the qca-wireless checkout).

## Provenance

| File | Origin | md5 |
|---|---|---|
| upstream `board-8devices_kiwi.qcn9274` | qca-wireless 3eba07d9 (2026-09-27), 14 board images + 1 regdb | e8a1bc39f9aa12caa4a271b626f99af8 |
| `bdwlan.b000c` | Qualcomm BDF for the 8devices Noni wideband profile, from the 8devices firmux-kiwi tree (`package/firmware/qcn9224-firmware/files/bdwlan.b000c`, QSDK data set) | b24e9c2fca8603f3f95b0f6442dce281 |
| `board-8devices_kiwi.qcn9274` (shipped) | upstream file + one board image named `bus=pci,qmi-chip-id=0,qmi-board-id=12` whose payload is `bdwlan.b000c` | 8e4f9ae92ef1de9325d752c64172c1fe |

The shipped file is generated, not taken from a vendor image. Verified on
Kiwi-DVK 2026-09-29..10-01 with QCN9274 firmware WLAN.WBE.1.4.1-00199: Noni
id 12 (5/6 GHz wideband), Noni id 4 (6 GHz), SoM 2.4 GHz and SoM 5/6 GHz
sub-radios all up.

Noni profiles: 6 GHz only = board-id 4 (upstream has it), wideband = 12
(0x000c, this entry), split = 0x1006 (not added, untested).

## Rebuilding

    scripts/make-kiwi-board.sh <upstream board-8devices_kiwi.qcn9274> [out]

uses `ath12k-bdencoder` (qca-swiss-army-knife) to extract the upstream file,
append the id-12 image and create a new container. The result has identical
images (encoder diffstat: 0 added / 0 changed / 0 deleted) but a different
byte layout: the shipped file appends the id-12 image after the regdb, the
encoder writes all board images before the regdb. ath12k matches images by
name, so both are equivalent; the shipped binary stays canonical because it
is the hardware-verified one.

## SBOM

This file is a permanent part of the overlay; the id-12 entry is not
submitted to qca-wireless. The package version of `ipq-wifi-8devices_kiwi`
in the image SBOM is the qca-wireless commit the container was built from,
so `scripts/sbom-pedigree.py` adds a pedigree note to that component naming
this directory, the extra entry and the md5 of the installed file.
