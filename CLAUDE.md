# pi-panel-image

Builds the pi-panel OS image with rpi-image-gen (see README.md). The plans
are in `~/.claude/plans/pi-panel-roadmap.md` (this repo is plan 4).

- Builds run on **starscream** (Pi 4, 1.8 GiB RAM, trixie): manual builds as
  `matt` with work in `/srv/build/rig-work` and output in `/srv/build/rig-out`.
  Never put build output on its 8 GB iSCSI root. `runner/` holds the runner's
  notes and the `tftp-kernel` tool that boots it.
- rpi-image-gen basics that matter here:
  - layers are YAML with a `METABEGIN` header; `<layer>.d/customize.overlay/`
    is copied into the root and `<layer>.d/hooks/customizeNN-*` run with the
    root as `$1` (they `chroot` into it, with network).
  - `/etc` on a device is an overlay on tmpfs: anything written there is lost
    at reboot unless declared `EarlyPersistFile=` in `slot-shared.d`.
    Accounts are (all four files), so `sysusers.d/pi-panel.conf` re-creates
    the service user when an older stored `/etc/passwd` lacks it.
  - each slot's `/var` is reset from the image (`/usr/share/factory/var`) on
    the first boot after an update, if the image's `SOURCE_DATE_EPOCH` is newer.
  - `ig metadata --lint layer/<x>.yaml` checks a layer (needs pyyaml,
    python-debian, jsonschema).
- The layout contract of pi-panel-core (CLAUDE.md there) applies: everything
  is built in place under `/opt/pi-panel` in the target root.
- Push to `origin` (Forgejo) only when asked.
