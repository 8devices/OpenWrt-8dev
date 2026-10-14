#!/bin/sh
# Rebuild the 8devices Kiwi QCN9274 board-2.bin that carries the Noni
# wideband profile (qmi-board-id=12) and check it against the shipped file.
#
# Usage: scripts/make-kiwi-board.sh <upstream board-8devices_kiwi.qcn9274> [out]
#
#   upstream  pristine file from the qca-wireless repo (OpenWrt: dl/ipq-wifi-*.tar.zst)
#   out       output path (default: ./board-8devices_kiwi.qcn9274.new)
#
# Needs python3 and ath12k-bdencoder from qca-swiss-army-knife
# (BDENCODER=/path/to/ath12k-bdencoder, or on PATH, or the repo is cloned
# into a temp dir). The id-12 payload is board-files/8devices_kiwi/bdwlan.b000c.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
upstream=${1:?usage: $0 <upstream board-8devices_kiwi.qcn9274> [out]}
out=${2:-board-8devices_kiwi.qcn9274.new}
case $out in /*) ;; *) out=$(pwd)/$out ;; esac    # the script cds into a temp dir
bdf=$here/board-files/8devices_kiwi/bdwlan.b000c
ref=$here/board-files/8devices_kiwi/board-8devices_kiwi.qcn9274
name='bus=pci,qmi-chip-id=0,qmi-board-id=12'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

enc=${BDENCODER:-$(command -v ath12k-bdencoder || true)}
if [ -z "$enc" ]; then
	git clone -q --depth 1 https://github.com/qca/qca-swiss-army-knife.git "$work/sak"
	enc=$work/sak/tools/scripts/ath12k/ath12k-bdencoder
fi

upstream=$(cd "$(dirname "$upstream")" && pwd)/$(basename "$upstream")
mkdir -p "$work/x" && cd "$work/x"
python3 "$enc" -e "$upstream" >/dev/null
json=$(ls ./*.json | head -1)
cp "$bdf" ./bdwlan.b000c

python3 - "$json" "$name" <<'PY'
import json, sys
path, name = sys.argv[1], sys.argv[2]
data = json.load(open(path))
boards = data[0]["board"]
if not any(name in b["names"] for b in boards):
    boards.append({"names": [name], "data": "bdwlan.b000c"})
json.dump(data, open(path, "w"), indent=4)
PY

python3 "$enc" -c "$json" -o "$out" >/dev/null
echo "created $out"
if [ -f "$ref" ]; then
	if cmp -s "$out" "$ref"; then
		echo "identical to shipped $ref"
	else
		echo "byte layout differs from shipped $ref (expected: the shipped file"
		echo "appends the id-12 entry after the regdb, the encoder writes boards first)."
		echo "Content comparison (0 added/changed/deleted means identical images):"
		python3 "$enc" -D "$ref" "$out" | grep -E "image\(s\)" || true
	fi
fi
