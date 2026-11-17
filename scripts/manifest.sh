#!/bin/bash
# manifest.sh <the image root's /var/lib/dpkg> <pi-panel-release>
#
# What the image contains, for comparing panels with a release (jazz's
# drift check) and for review: the release file, the kernel and every
# installed package with its version.
set -euo pipefail

admin=$1
[ -f "$admin/status" ] || { echo "no dpkg status in $admin" >&2; exit 1; }

echo "# pi-panel-release"
cat "$2"
echo
echo "# kernel"
dpkg-query --admindir="$admin" -W -f='${Package} ${Version}\n' 'linux-image-*' 2>/dev/null || true
echo
echo "# packages"
dpkg-query --admindir="$admin" -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' \
    | awk '$1 == "ii" { print $2, $3 }'
