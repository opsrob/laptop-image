# laptop-image

A custom [bootc](https://bootc.dev/) image for my laptop (Framework, 12th Gen Intel), built on [Fedora Silverblue](https://fedoraproject.org/atomic-desktops/silverblue/) 45. GitHub Actions rebuilds it every day on top of the latest Silverblue base, then signs it and publishes it to `ghcr.io/opsrob/laptop-image:latest`. The laptop stages each new build in the background and switches to it on the next reboot.

Everything the old Ansible playbook installed on a mutable Fedora system is built into the image instead. Dotfiles are not: they're managed separately with [chezmoi](https://www.chezmoi.io/).

## Using the image

### Switching an existing Silverblue install

From any Fedora Atomic / bootc system:

```bash
sudo bootc switch ghcr.io/opsrob/laptop-image:latest
systemctl reboot
```

### Fresh install

Run the **Build disk images** workflow (Actions → Build disk images → Run workflow) to produce an Anaconda installer ISO and a qcow2 VM image. Both are uploaded as job artifacts, or to S3 if you tick *Upload to S3* (that needs the `S3_*` repository secrets). The installer's kickstart (`disk_config/iso.toml`) points the new install at `ghcr.io/opsrob/laptop-image:latest`, so later updates come from the registry.

### Updates and rollback

- `rpm-ostreed-automatic.timer` runs with `AutomaticUpdatePolicy=stage`. New images are downloaded and staged in the background and take effect on the next reboot, whenever you choose to reboot.
- GNOME Software handles Flatpak updates.
- Common commands:

  ```bash
  bootc status              # booted, staged and rollback images
  sudo bootc upgrade        # fetch and stage the latest image now
  sudo bootc rollback       # boot the previous image next time
  ```

### Verifying the signature

Published images are signed with cosign. The public key is `cosign.pub` in this repo:

```bash
cosign verify --key cosign.pub ghcr.io/opsrob/laptop-image:latest
```

## What's in the image

The base is `quay.io/fedora/fedora-silverblue:45`, tracked by tag rather than digest so the daily build always picks up Fedora's latest base. Everything below is added in [`build_files/build.sh`](build_files/build.sh), which also comments on why each workaround is there.

**Codecs and hardware video:** RPM Fusion (free and nonfree), with full `ffmpeg` and `intel-media-driver` (iHD VAAPI) replacing Fedora's patent-stripped builds, plus the GStreamer freeworld/ugly/libav plugins.

**Third-party repos:** VS Code, 1Password, HashiCorp, Google Chrome (plain `.repo` files in `system_files/`), ProtonVPN (release RPM), OpenTofu (official install script) and the `scottames/ghostty` COPR.

**Packages:** development tools, Python, Go, Node 24, Java 25, VS Code, Terraform/OpenTofu, `gh`, chezmoi, age, Ghostty, Chrome, 1Password, Thunderbird, GIMP, Inkscape, Audacity, VLC, qBittorrent, GNOME Boxes, ProtonVPN, `fuse-libs` (libfuse2, so AppImages run), and hardware diagnostics (`lm_sensors`, `powertop`, `smartmontools`, `inxi`, `hwinfo`, …).

**Vendor releases, always the latest at build time:**

| Software | Source |
| --- | --- |
| Proton Mail Bridge | GitHub release RPM, signature checked against Proton's key |
| Proton Mail desktop | Proton's `version.json`, SHA512 checked |
| Proton Drive CLI | Proton's `version.json`, SHA512 checked |
| Libation | GitHub release RPM |
| Ente Photos | GitHub release RPM |
| Zoom | zoom.us RPM |
| tflint | GitHub release zip |
| goat (Bluesky atproto CLI) | GitHub release, checksum checked |
| AWS CLI v2 | AWS installer zip |
| aws-cdk, dnspython, virtualenv | npm / pip into `/usr` |

**Flatpaks** (from Flathub, via [`flatpak-preinstall.service`](system_files/usr/lib/systemd/system/flatpak-preinstall.service) and [`laptop-image.preinstall`](system_files/etc/flatpak/preinstall.d/laptop-image.preinstall)): Zotero, Signal, Vivaldi, Obsidian, Plex, Calibre, Gear Lever (AppImage manager). The preinstall list is re-applied on every boot. Silverblue's Fedora Flatpak remote is disabled, so apps come only from Flathub.

**System configuration** (all under [`system_files/`](system_files/)):

- Kernel args for the Framework (`nvme.noacpi=1`, `i915.enable_psr=0`, `module_blacklist=hid_sensor_hub`), in `usr/lib/bootc/kargs.d/`
- Power defaults: the Performance profile is set on first boot by `laptop-image-power-defaults.service`; battery percentage is shown and the laptop never auto-suspends on AC (set through dconf)
- A udev rule that keeps the dock's Realtek 2.5G USB NIC on the `r8152` driver
- Daily user timers that pull CloudFront logs (`cloudfront-logs-pull@{opsrob,dontcall}.timer`). The scripts and credentials they use come from the dotfiles, not the image
- A bind mount that makes `/opt/IDriveForLinux` writable for IDrive
- Automatic staged updates, `podman.socket`, `crond`, and the Plymouth `details` theme

### Not in the image, by design

- **Dotfiles:** managed with chezmoi.
- **IDrive:** installed by hand after boot into the writable bind mount. The steps are in [`opt-IDriveForLinux.mount`](system_files/usr/lib/systemd/system/opt-IDriveForLinux.mount).
- **hugo:** installed with Homebrew from the dotfiles.
- **snapd, dkms/out-of-tree kernel modules:** left out deliberately; `build.sh` explains why.

## Repository layout

| Path | Purpose |
| --- | --- |
| [`Containerfile`](Containerfile) | Base image, makes `/opt` part of the image, runs `build.sh`, runs `bootc container lint` |
| [`build_files/build.sh`](build_files/build.sh) | All package installs and image configuration |
| [`system_files/`](system_files/) | Copied over `/` at build time: repo files, systemd units, dconf, udev, kargs |
| [`disk_config/`](disk_config/) | bootc-image-builder configs for the ISO (`iso.toml`) and qcow2/raw (`disk.toml`) |
| [`image-template.env`](image-template.env) | Image name, organisation and metadata labels |
| [`.github/workflows/build.yml`](.github/workflows/build.yml) | Daily, push and PR image build; push and sign on `main` |
| [`.github/workflows/build-disk.yml`](.github/workflows/build-disk.yml) | Manual ISO/qcow2 build |
| [`cosign.pub`](cosign.pub) | Public key for verifying image signatures |

## CI

[`build.yml`](.github/workflows/build.yml) runs:

- every day at 10:05 UTC,
- on every push to `main` (README-only changes don't trigger it),
- on pull requests,
- and on demand.

It builds the image, rechunks it with rpm-ostree so updates download as smaller deltas, then tags it `latest`, `latest-<YYYYMMDD>` and `<YYYYMMDD>`, plus variants with the short git SHA (`latest-<sha>`, `<YYYYMMDD>-<sha>`, …). Pull requests are built but never pushed or signed. On `main`, the image is pushed to GHCR and signed with the cosign private key stored in the `SIGNING_SECRET` repository secret.

The build's GitHub release lookups use the workflow's `GITHUB_TOKEN`, passed in as a build secret, to avoid api.github.com rate limits.

Dependency updates:

- Dependabot opens PRs for GitHub Actions, and `dependabot-automerge.yml` turns on auto-merge for minor and patch bumps, so they merge once the PR build passes. That needs branch protection on `main`; without it the job fails and the PR has to be merged by hand.
- Renovate keeps action digests pinned and is configured not to digest-pin the Silverblue base.

## Building and testing locally

Build with podman from the repo root. The secret is optional; it only avoids GitHub API rate limits:

```bash
GITHUB_TOKEN=$(gh auth token) \
  podman build --pull=newer --secret id=gh_token,env=GITHUB_TOKEN \
    -t localhost/laptop-image:latest -f Containerfile .
```

To boot a local build, it has to be in root's container storage. Build it with `sudo podman build …` (same arguments), or copy it across with `podman image scp`. Then:

```bash
sudo bootc switch --transport containers-storage localhost/laptop-image:latest
systemctl reboot
```

Switch back to the published image with `sudo bootc switch ghcr.io/opsrob/laptop-image:latest`.

To try it in a VM first, build a qcow2 with [bootc-image-builder](https://osbuild.org/docs/bootc/):

```bash
mkdir -p output
sudo podman run --rm -it --privileged --pull=newer \
  --security-opt label=type:unconfined_t \
  -v ./disk_config/disk.toml:/config.toml:ro \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 --use-librepo=True localhost/laptop-image:latest
```

Then open `output/qcow2/disk.qcow2` in GNOME Boxes or `virt-install`.

## Maintenance notes

- **New Fedora release:** bump the tag in `Containerfile` (`fedora-silverblue:45` → `46`). Check that the versioned package names in `build.sh` (`nodejs24`, `java-25-openjdk-headless`) still exist, and that the ProtonVPN release RPM URL has a directory for the new release.
- **Adding a Flatpak:** add a `[Flatpak Preinstall <app-id>]` entry to `system_files/etc/flatpak/preinstall.d/laptop-image.preinstall`.
- **Vendor RPMs with scriptlets:** a `%post` that expects a running system (D-Bus, sysctl, desktop database) fails the whole `dnf5` transaction in a container build. Install those with `--setopt=tsflags=noscripts` and redo any step that's actually needed explicitly, as `build.sh` does for ProtonVPN and Libation.
- **Anything under `/var`** (Flatpak installs, `/usr/local`, keyring trust) doesn't carry over from the build into a deployed system. Put it in `/usr` or `/etc`, or do it on first boot with a systemd unit.
- **Known issue, Fedora 45:** the Secret Service is oo7-daemon (a 0.7.0 beta), which has a race ([oo7#652](https://github.com/linux-credentials/oo7/issues/652)) that makes Proton Bridge's keychain self-test fail with "Bridge failed to start". Workaround: set `"DisableTest": true` in `~/.config/protonmail/bridge-v3/keychain.json` until Fedora ships oo7 0.7.1 or later.
