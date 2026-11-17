#!/bin/bash
# check-sizes.sh <image outputdir> <system slot size> <boot slot size>
#
# Slots can't grow by an update (only a re-flash), so catch growth early:
# warn above 70% of a slot, fail above 85%. Measures genimage's parts:
# system.erofs (the root filesystem) and boot.img (the boot files, which
# boot.vfat wraps).
set -euo pipefail

dir=$1
bytes() { numfmt --from=iec "$1"; }
used() { echo $(( $(stat -c '%b' "$1") * $(stat -c '%B' "$1") )); }   # allocated, not apparent
status=0
check() {   # check <label> <file> <slot size>
    local file=$2 slot pct
    [ -f "$file" ] || { echo "   $1: $file missing" >&2; status=1; return; }
    slot=$(bytes "$3")
    pct=$(( $(used "$file") * 100 / slot ))
    printf '   %-6s %s of %s (%d%%)\n' "$1" "$(numfmt --to=iec "$(used "$file")")" "$3" "$pct"
    if [ "$pct" -gt 85 ]; then
        echo "   error: $1 is above 85% of its slot" >&2; status=1
    elif [ "$pct" -gt 70 ]; then
        echo "   warning: $1 is above 70% of its slot" >&2
    fi
}
check system "$dir/system.erofs" "$2"
check boot "$dir/boot.img" "$3"
exit $status
