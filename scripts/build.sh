#!/bin/bash
# Build a pi-panel OS image from release.toml.
#
#   scripts/build.sh [--variant release|dev] [--version V] [--work DIR] [--out DIR]
#
# 1. checks out rpi-image-gen at the pinned commit (in the work dir)
# 2. fetches each component at its tag and a pinned uv, and writes
#    pi-panel-release (os-release style) with the tags and commits
# 3. runs rpi-image-gen with config/pi-panel.yaml; the pi-panel layers
#    build everything in place in the target root
# 4. checks the slot sizes (warn above 70%, fail above 85%), then writes
#    pi-panel-<version>-rpi5.img.xz, pi-panel-<version>-rpi5.manifest.txt and
#    SHA256SUMS to the output dir
#
# Run it as forgejo-runner on starscream. Work and output default to the
# 82G build disk (/srv/build), never the 8 GB iSCSI root.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
VARIANT=release
VERSION=
WORK=/srv/build/rig-work
OUT=/srv/build/rig-out

while [ $# -gt 0 ]; do
    case $1 in
        --variant) VARIANT=$2; shift 2 ;;
        --version) VERSION=$2; shift 2 ;;
        --work)    WORK=$2; shift 2 ;;
        --out)     OUT=$2; shift 2 ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

case $VARIANT in
    release) ;;
    dev) echo "the dev variant is not built yet (plan 4 step G)" >&2; exit 2 ;;
    *) echo "--variant must be release or dev" >&2; exit 2 ;;
esac

# release.toml as shell assignments (python3's tomllib: no extra dependency).
eval "$(python3 - "$REPO/release.toml" <<'EOF'
import shlex, sys, tomllib
r = tomllib.load(open(sys.argv[1], "rb"))
out = {"REL_VERSION": r["version"], "RIG_URL": r["rpi-image-gen"]["url"],
       "RIG_COMMIT": r["rpi-image-gen"]["commit"], "UV_VERSION": r["uv"]["version"]}
core = r["components"]["pi-panel-core"]
out |= {"CORE_URL": core["url"], "CORE_TAG": core["tag"]}
apps = [(n, c["url"], c["tag"]) for n, c in r["components"].items() if c.get("kind") == "app"]
out["APP_NAMES"] = " ".join(n for n, _, _ in apps)
for n, url, tag in apps:
    key = n.upper().replace("-", "_")
    out[f"URL_{key}"], out[f"TAG_{key}"] = url, tag
for k, v in out.items():
    print(f"{k}={shlex.quote(v)}")
EOF
)"
VERSION=${VERSION:-$REL_VERSION}
if ! [[ $VERSION =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]+(-dev\.[0-9]+)?$ ]]; then
    echo "version $VERSION: want YYYY.MM.N or YYYY.MM.N-dev.N" >&2
    exit 2
fi
NAME=pi-panel-$VERSION-rpi5
[ "$VARIANT" = release ] || NAME=pi-panel-$VARIANT-$VERSION-rpi5

SRC=$WORK/src
RIG=$WORK/rpi-image-gen
CACHE=$WORK/cache
mkdir -p "$WORK" "$OUT" "$CACHE" "$WORK/tmp"
# rpi-image-gen and genimage stage whole partitions in $TMPDIR; starscream's
# /tmp is a small tmpfs.
export TMPDIR=$WORK/tmp
rm -rf -- "${SRC:?}" && mkdir -p "$SRC"
echo "== pi-panel $VERSION ($VARIANT), work $WORK"

echo "== rpi-image-gen $RIG_COMMIT"
if [ ! -d "$RIG/.git" ]; then git clone -q "$RIG_URL" "$RIG"; fi
git -C "$RIG" fetch -q origin
git -C "$RIG" checkout -q --detach "$RIG_COMMIT"

fetch() {   # fetch <url> <tag> <dest>: a shallow checkout of one tag
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$2" "$1" "$3"
    git -C "$3" rev-parse HEAD
}
echo "== components"
CORE_COMMIT=$(fetch "$CORE_URL" "$CORE_TAG" "$SRC/pi-panel-core")
rm -rf "$SRC/pi-panel-core/.git"
echo "   pi-panel-core $CORE_TAG $CORE_COMMIT"
: > "$SRC/apps.txt"
COMPONENTS="pi-panel-core=$CORE_TAG@$CORE_COMMIT"
for n in $APP_NAMES; do
    key=${n^^}; key=${key//-/_}
    url_var=URL_$key; tag_var=TAG_$key
    # Only to record the commit: pi-panel-pkg fetches it again in the chroot.
    # An annotated tag's ^{} line is the commit; a lightweight tag only has the plain line.
    commit=$(git ls-remote "${!url_var}" "refs/tags/${!tag_var}" "refs/tags/${!tag_var}^{}" \
             | sort -k2 | tail -n1 | cut -f1)
    [ -n "$commit" ] || { echo "tag ${!tag_var} not found in ${!url_var}" >&2; exit 1; }
    echo "${!url_var}#${!tag_var}" >> "$SRC/apps.txt"
    COMPONENTS="$COMPONENTS $n=${!tag_var}@$commit"
    echo "   $n ${!tag_var} $commit"
done

echo "== uv $UV_VERSION"
uvtar=$CACHE/uv-$UV_VERSION-aarch64-unknown-linux-gnu.tar.gz
if [ ! -f "$uvtar" ]; then
    curl -fsSL -o "$uvtar.part" \
        "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-aarch64-unknown-linux-gnu.tar.gz"
    mv "$uvtar.part" "$uvtar"
fi
tar -xzf "$uvtar" -C "$SRC" --strip-components=1 uv-aarch64-unknown-linux-gnu/uv uv-aarch64-unknown-linux-gnu/uvx

BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$SRC/pi-panel-release" <<EOF
NAME="pi-panel"
VERSION="$VERSION"
VARIANT="$VARIANT"
LAYOUT=1
SYSTEM_PART_SIZE=4G
BOOT_PART_SIZE=256M
UPDATE_CHANNEL_DEFAULT="$( [ "$VARIANT" = dev ] && echo dev || echo stable )"
COMPONENTS="$COMPONENTS"
RPI_IMAGE_GEN="$RIG_COMMIT"
BUILD_DATE="$BUILD_DATE"
EOF

echo "== rpi-image-gen build"
rm -rf -- "${WORK:?}/build" && mkdir -p "$WORK/build"
"$RIG/rpi-image-gen" build -S "$REPO" -c pi-panel.yaml -B "$WORK/build" -- \
    "IGconf_pipanel_srcdir=$SRC" \
    "IGconf_pipanel_variant=$VARIANT" \
    "IGconf_artefact_version=$VERSION" \
    "IGconf_deploy_compression=none"

# The paths follow IGconf_sys_workroot (-B), IGconf_artefact_version and the
# image name (no find: parts of the tree are only readable in the build's
# user namespace).
img=$WORK/build/deploy-$VERSION/pi-panel.img
imgout=$WORK/build/image-pi-panel                       # genimage's parts
rootfs=$WORK/build/chroot-$VERSION/filesystem
[ -f "$img" ] || { echo "no image at $img" >&2; exit 1; }

echo "== slot size check"
"$REPO/scripts/check-sizes.sh" "$imgout" 4G 256M

echo "== outputs in $OUT"
rm -f -- "${OUT:?}/${NAME:?}".*
xz -T2 -6 -c "$img" > "$OUT/$NAME.img.xz"
"$REPO/scripts/manifest.sh" "$rootfs/usr/share/factory/var/lib/dpkg" "$SRC/pi-panel-release" > "$OUT/$NAME.manifest.txt"
cp "$SRC/pi-panel-release" "$OUT/$NAME.release"
(cd "$OUT" && sha256sum "$NAME.img.xz" "$NAME.manifest.txt" "$NAME.release" > "$NAME.SHA256SUMS")
ls -la "$OUT/$NAME".*
