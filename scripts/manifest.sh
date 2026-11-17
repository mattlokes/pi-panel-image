#!/bin/bash
# manifest.sh <rpi-image-gen workroot> <pi-panel-release>
#
# What the image contains, for comparing panels with a release (jazz's
# drift check) and for review: the release file, the kernel and every
# installed package with its version.
set -euo pipefail

status=$(find "$1" -path '*/var/lib/dpkg/status' -not -path '*/proc/*' -print -quit)
[ -n "$status" ] || { echo "no dpkg status under $1" >&2; exit 1; }
admin=$(dirname "$status")

echo "# pi-panel-release"
cat "$2"
echo
echo "# kernel"
dpkg-query --admindir="$admin" -W -f='${Package} ${Version}\n' 'linux-image-*' 2>/dev/null || true
echo
echo "# packages"
dpkg-query --admindir="$admin" -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' \
    | awk '$1 == "ii" { print $2, $3 }'
