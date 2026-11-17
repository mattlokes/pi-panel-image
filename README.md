# pi-panel-image

Builds the pi-panel OS image for the Raspberry Pi 5 with
[rpi-image-gen](https://github.com/raspberrypi/rpi-image-gen): Debian trixie
minbase, the `image-rota` GPT A/B layout with a read-only erofs root, and
pi-panel (core plus the apps in `release.toml`) built in place under
`/opt/pi-panel`. Updates (RAUC bundles, tryboot) come in plan 5.

## Layout of a device

| Partition | Size | What |
|---|---|---|
| `bootconfig` | 32M | `/bootfs` (FAT, rw): `autoboot.txt`, the optional `pi-panel/` provisioning folder |
| `boot_a`, `boot_b` | 256M each | kernel, initramfs, DTBs (one slot each) |
| `system_a`, `system_b` | 4G each | the read-only root (erofs) |
| `persistent` | the rest | `/persistent`: `pi-panel/{config,state,home}`, `/home`, the journal, each slot's `/var` |

The raw image is about 9.5 GiB, so **16 GB is the smallest drive**. On the
smallest 16 GB cards (about 14.4 GiB) `persistent` grows to about 5.9 GiB on
first boot.

Slots can't be resized by an update. A release that outgrows them needs a
re-flash: back up `/persistent/pi-panel/config` (`pi-panel-ctl config
export`), flash, and restore it through the provisioning folder. The build
warns when a slot is above 70% full and fails above 85%.

## Building

On starscream (Pi 4, trixie, arm64), as `matt` for manual builds:

```bash
scripts/build.sh                 # release image of release.toml's version
scripts/build.sh --version 2026.11.0-dev.1
```

It writes to `/srv/build/rig-out`:
- `pi-panel-<version>-rpi5.img.xz`: flash with Raspberry Pi Imager ("Use custom") or `xzcat … | dd`
- `….manifest.txt`: the release file, the kernel and every package version
- `….release`: `/etc/pi-panel-release` of the image
- `….SHA256SUMS`

`release.toml` pins everything: rpi-image-gen's commit, uv, and each
component's tag. Component tags are pushed before a build; the build fetches
them from Forgejo.

## The layers

- `layer/pi-panel-build.yaml`: installs the build tools, builds the core in
  place (compositor, three venvs), installs the apps into the image registry
  with `pi-panel-pkg install --image`, then purges the build tools.
- `layer/pi-panel.yaml`: runtime packages (the core's PACKAGES.md plus every
  app's `[system]`), the `pi-panel` service user (UID/GID 900, also in
  `sysusers.d`), pi-panel-core's `deploy/install.sh`, `/etc/pi-panel-release`,
  the journal cap and first boot.

## First boot and provisioning

`pi-panel-firstboot.service` grows `persistent` to fill the drive and imports
`/bootfs/pi-panel/` if it is there, then deletes it (it holds secrets). Put
the folder on the card's boot partition (the FAT one a PC shows) before the
first boot, or any time later:

```
pi-panel/
  panel.toml            # pi-panel-ctl's config
  compositor.env        # optional
  apps/<name>/…         # app config
  authorized_keys       # for the login user (pi)
  password-hash         # e.g. `openssl passwd -6`; without it the login has no password
  hostname
  wifi/<SSID>.psk       # iwd profiles: [Security] Passphrase=…
```

The login user is `pi` (`device.user1` in `config/pi-panel.yaml`); without
`authorized_keys` or `password-hash` it can't log in. Raspberry Pi Imager's
OS customisation writes cloud-init/firstrun files that this minbase image
does not run, so the folder is the way to provision.

Accounts, the hostname, ssh host keys and wifi profiles survive updates
(rpi-image-gen's `slot-shared.d`, see `layer/pi-panel.d/`).
