# starscream: the pi-panel CI runner

This is how the Forgejo Actions runner for pi-panel is set up.
- It lives in `pi-panel-image/runner/` (moved from `/srv/build/runner-notes/` in plan 4), together with `tftp-kernel/`. The copies on starscream are the old ones.
- It was written during plan 1, Step 2, on 2026-11-08.

## Host

- **Hardware and OS:** Raspberry Pi 4 with 1.8 GiB RAM, Debian 13 trixie arm64, kernel 6.18.50+rpt-rpi-v8 (booted over TFTP).
- **Root:** an 8G iSCSI disk. After Step 2, 3.9G is free.
- **USB disk:**
  - `/var/lib/forgejo-runner/cache` (32G), which holds the actcache and the uv cache;
  - `/srv/build` (82G), which holds the job workdirs in `/srv/build/runner` and the swapfile.
- **Swap:** 4G swapfile plus about 923M zram.
- **Runner:** forgejo-runner v13.2.1, user `forgejo-runner`, host executor, label `arm64`, capacity 1, registered instance-wide.

## apt packages (Step 2)

Installed with `--no-install-recommends` from Debian trixie plus `archive.raspberrypi.com/debian trixie main`. That added 227 packages and about 400 MB.

```
# Compositor build: pi-panel-core/PACKAGES.md "Build only" (libwlroots-0.19 runtime comes in as a Depends)
libwlroots-0.19-dev          # 0.19.1-1+rpt5, from archive.raspberrypi.com
libwayland-dev
libwayland-bin
wayland-protocols
libxkbcommon-dev
libpixman-1-dev
libdrm-dev
meson
ninja-build

# Typelibs, so CI can import every app module (gi.require_version / from gi.repository)
python3-gi                   # now-playing (venv with --system-site-packages), webrtc-client (system python)
gir1.2-gtk-4.0               # now-playing: Gtk/Gdk/Gsk/Graphene 4, Pango
python3-gst-1.0              # webrtc-client: Gst plus the gst-python overrides
python3-gi-cairo             # webrtc-client: gi.require_foreign("cairo")
gir1.2-pango-1.0             # webrtc-client: Pango / PangoCairo
gir1.2-gst-plugins-bad-1.0   # webrtc-client: GstSdp / GstWebRTC
```

These were already present from the base system: `git`, `build-essential` (gcc), `pkg-config`, `python3` 3.13.5, `curl`, `ca-certificates`, `xkb-data`, and `systemd` 257 (`varlinkctl`, which the IDL tests use).

### Not installed on purpose

| Packages | Why not |
|---|---|
| `gstreamer1.0-plugins-bad`, `-plugins-good`, `-libav`, `-nice` | webrtc-client's GStreamer runtime elements. CI doesn't build pipelines; the tests are offline, and the pipeline is checked live on the Pi. About 150 more packages, including ffmpeg and onnxruntime, on an 8G root. |
| `libegl1`, `libgl1`, `libwayland-egl1`, `libwayland-cursor0` | immich's SDL dlopen libraries, which are only needed when it renders. Most already come in through the wlroots/GTK Depends. |
| GTK's Recommends | Same as on the panels (see now-playing's PACKAGES.md). |

Snapshots: `dpkg-before-step2.txt` and `dpkg-after-step2.txt`, both in this directory.

## Not from apt

- **uv 0.12.10**, the same version as jazz and prime, is at `/var/lib/forgejo-runner/.local/bin/{uv,uvx}`, owned by `forgejo-runner`.
  - Source: the GitHub release `uv-aarch64-unknown-linux-gnu.tar.gz`, verified against its `.sha256`.
  - To upgrade, repeat with the new version, and keep it in step with the panels.

## Runner config changes (`/etc/forgejo-runner/config.yml`)

The backup is `config.yml.bak-2026-11-08`. The change is to `runner.envs`, which every job sees:

```yaml
PATH: /var/lib/forgejo-runner/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
UV_CACHE_DIR: /var/lib/forgejo-runner/cache/uv   # on the USB disk, not the 8G root
```

Apply changes with `sudo systemctl restart forgejo-runner`, then check that it logs "declared successfully".

## Image builds (plan 4, 2026-11-17)

rpi-image-gen at the commit in `release.toml`, in `/srv/build/rig-work/rpi-image-gen`.
- `sudo rpi-image-gen/install_deps.sh` added 85 packages (`dpkg-before-rig.txt`
  and `dpkg-after-rig.txt` in `/srv/build/rig-work`), with podman for its
  `podman unshare` namespaces. No `linux-*` or `rpi-eeprom` package changed.
- `/srv/build/rig-work` (work) and `/srv/build/rig-out` (images) are owned by
  `matt`, who runs the manual builds; `matt` has subuid/subgid `100000:65536`
  and linger, so a build runs as a `systemd-run --user` unit.
- rpi-image-gen builds its own erofs-utils, genimage, zstd, util-linux and
  bdebstrap into its work tree, so host versions of those don't matter.

```
aardvark-dns arch-test autoconf automake autopoint autotools-dev btrfs-progs 
buildah catatonit cmake cmake-data conmon containernetworking-plugins 
containers-storage criu crun cryptsetup cryptsetup-bin dctrl-tools flex 
fuse-overlayfs fuse3 golang-github-containers-common 
golang-github-containers-image javascript-common libarchive13t64 libcompel1 
libcriu2 libdistro-info-perl libexpat1-dev libexpat1 libfl-dev libfl2 
libflac14 libjs-jquery libjs-sphinxdoc libjs-underscore libjson-c5 
libjsoncpp26 libltdl-dev libltdl7 libnet1 libprotobuf-c1 libprotobuf32t64 
libpython3-dev libpython3.13-dev libreiserfscore0t64 librhash1 libslirp0 
libsubid5 libtool libyajl2 m4 mmdebstrap mtools netavark passt podman pv 
python3-arrow python3-attr python3-dateutil python3-debian python3-dev 
python3-fqdn python3-isoduration python3-json-pointer python3-jsonschema 
python3-jsonschema-specifications python3-pip python3-protobuf python3-pycriu 
python3-referencing python3-rfc3339-validator python3-rfc3986-validator 
python3-rfc3987 python3-rpds-py python3-typeshed python3-uritemplate 
python3-webcolors python3-wheel python3.13-dev slirp4netns uidmap 
uuid-runtime 
```

## Rules

- **Kernel holds:** don't touch them. The published TFTP kernels stay on `apt-mark hold`, and Step 2 changed no `linux-*` or `rpi-eeprom` package. See the memory note and `tftp-kernel`.
- **Builds:** `-j2` or lower. Never put `-march`, `-mcpu` or `native` in build flags, because Pi 4 builds must stay valid on the Pi 5.
- **Trust:** the host executor runs jobs directly as `forgejo-runner`. Only trusted repos may use the runner, and Actions on fork pull requests stay off or need approval.

## Smoke test (2026-11-08)

The CI commands were run by hand as `forgejo-runner`, with the job env, on copies of the repos:

| Step | Result |
|---|---|
| compositor `meson setup build && ninja -C build -j2` | ok, 20/20 targets, 5s |
| ctl `uv sync --frozen --all-packages && uv run --frozen pytest` | 86 passed |
| pluginman `uv sync --frozen && uv run --frozen pytest` | 44 passed |
| now-playing venv (`--system-site-packages`) `+ uv sync --frozen && pytest` | 42 passed; GTK 4 module imports ok |
| immich `uv sync --script pi_panel_immich.py` | ok; it has no tests yet |
| webrtc-client `uv run --no-project --with pytest pytest` | 54 passed |
| webrtc-client import of `__main__`/`display`/`session` with the manifest `PYTHONPATH` | ok |

Peak use was well within RAM, swap went unused, and the uv cache came to 111M.
