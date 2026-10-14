#!/bin/sh
# 8devices OpenWrt quick start: patched tree + board config (+ build) in one go.
#
#   ./quick_start.sh [<config>] [options]        (run in the tree root)
#
# Steps:
#   1. prepare   make -C 8devices apply        (-n: FEEDS=no, patches only)
#   2. config    8devices/configs/<config>.config -> .config, make defconfig
#   3. keys      firmware signing key check (see 8devices/README.md, Keys)
#   4. compile   make -j$(nproc)                (only with -c)
#
# <config>: a name from 8devices/configs/ (-l lists them). Without one, a menu.
#
# Firmware signing key: key-build + key-build.pub in the tree root (generated
# by the first build, or copied in with -K). Required; never commit key-build.
#
# Examples:
#   ./quick_start.sh                      menu of configs, then prepare + defconfig
#   ./quick_start.sh kiwi-dvk -c          Kiwi DVK, and build right away
#   ./quick_start.sh lima -K ~/fw-keys    Lima, with the firmware signing key from ~/fw-keys
#   ./quick_start.sh mango-dvk -n         skip the feeds update (patches still applied)
#   ./quick_start.sh lima -d              show what would run
#
# Options:
#   -l, --list-configs     list the available configs and exit
#   -c, --compile          build after configuring
#   -C, --clean            make clean before anything else
#   -n, --no-feeds-update  do not update/install feeds (patches are still applied)
#   -K, --keys <dir>       copy key-build + key-build.pub from <dir> into the tree root
#   -d, --dry-run          print the commands instead of running them
#   -h, --help
set -eu

tree=$(cd "$(dirname "$0")" && pwd)
here=$tree/8devices
configs=$(cd "$here/configs" && ls *.config | sed 's/\.config$//')

config=
keys_dir=
clean=no
compile=no
feeds=yes
run=run

run() { "$@"; }
dry() { printf '%s\n' "$*"; }

usage() { sed -n '2,/^set -eu/{/^set -eu/d;s/^# \{0,1\}//;p}' "$0"; }

die() { echo "quick_start: $*" >&2; exit 1; }

list_configs() { printf '%s\n' $configs; }

# The firmware signing key: upstream's usign pair in the tree root, generated
# by the first build when missing. Gitignored upstream (key-build*).
copy_keys() {
	[ -d "$1" ] || die "no such directory '$1'"
	for f in key-build key-build.pub; do
		[ -s "$1/$f" ] || die "'$1/$f' missing or empty"
	done
	$run cp "$1/key-build" "$1/key-build.pub" "$tree/"
	$run rm -f "$tree/key-build.ucert"    # re-issued for the new key by the build
	$run chmod 600 "$tree/key-build"
	echo "firmware signing key copied from $1"
}

keys_step() {
	[ -z "$keys_dir" ] || copy_keys "$keys_dir"
	u=$tree/staging_dir/host/bin/usign
	if [ -s "$tree/key-build" ] && [ -s "$tree/key-build.pub" ]; then
		if [ -x "$u" ]; then
			echo "firmware signing key: $tree/key-build (present, fingerprint $("$u" -F -p "$tree/key-build.pub"))"
		else
			echo "firmware signing key: $tree/key-build (present)"
		fi
	else
		echo "firmware signing key: $tree/key-build (none yet, the first build generates it)"
	fi
	cat <<-EOT
	REQUIRED: CRA firmware is signed with key-build; devices accept only images
	signed with it. Back up key-build and key-build.pub. Never commit or share
	key-build (the private key).
	EOT
}

select_config() {
	[ -t 0 ] || die "no config given and no terminal for the menu; see -l"
	echo "Select a config:"
	i=1
	for c in $configs; do
		echo "  $i) $c"
		i=$((i + 1))
	done
	printf '> '
	read -r nr
	config=$(printf '%s\n' $configs | sed -n "${nr}p") 2>/dev/null
	[ -n "$config" ] || die "invalid selection"
}

while [ $# -gt 0 ]; do
	case $1 in
		-l|--list-configs) list_configs; exit 0 ;;
		-c|--compile) compile=yes ;;
		-C|--clean) clean=yes ;;
		-n|--no-feeds-update) feeds=no ;;
		-K|--keys) [ $# -ge 2 ] || die "--keys needs a directory"; keys_dir=$2; shift ;;
		-d|--dry-run) run=dry ;;
		-h|--help) usage; exit 0 ;;
		-*) die "unknown option $1 (see -h)" ;;
		*)
			[ -z "$config" ] || die "only one config may be given"
			config=$1
			;;
	esac
	shift
done

[ -n "$config" ] || select_config
[ -f "$here/configs/$config.config" ] || die "no such config '$config'; available: $(printf '%s ' $configs)"
[ -z "$keys_dir" ] || [ -d "$keys_dir" ] || die "no such directory '$keys_dir'"

cd "$tree"

if [ $clean = yes ]; then
	echo "== clean"
	$run make clean
fi

echo "== prepare (8devices overlay onto $(git rev-parse --short HEAD))"
$run make -s -C "$here" apply FEEDS=$feeds

echo "== config $config"
$run cp "$here/configs/$config.config" .config
$run make defconfig

echo "== keys"
keys_step

if [ $compile = yes ]; then
	echo "== compile"
	$run make -j"$(nproc 2>/dev/null || echo 1)"
else
	echo "== done; now: make -j\$(nproc)   (make menuconfig first only to change the predefined config)"
fi
