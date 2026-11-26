# Agent Instructions

A bootc image for the owner's laptop (Framework, 12th Gen Intel) built on Fedora
Silverblue 45 and published to `ghcr.io/opsrob/laptop-image:latest`. The laptop
stages each new build and switches on the next reboot. `README.md` is the full
reference (contents, CI, local builds, maintenance notes); read its
"Maintenance notes" before changing `build.sh`.

## Workflow

- Every change goes through a branch and pull request (squash, `(#N)` subjects).
- Merging to `main` publishes: CI builds, pushes to GHCR and cosign-signs, and the
  laptop picks it up on its next reboot. A broken build on `main` ships, so make
  sure the PR build passes. PR builds are never pushed or signed.
- `build.yml` also runs daily at 10:05 UTC on the latest Silverblue 45 base, so a
  build can break without any repo change (upstream package or release changes).
- Dependabot PRs for GitHub Actions auto-merge on minor/patch once the build passes.

## Layout

- `Containerfile`: base `quay.io/fedora/fedora-silverblue:45` (tracked by tag, not
  digest, on purpose), makes `/opt` real, runs `build_files/build.sh`, then
  `bootc container lint`.
- `build_files/build.sh`: all repo setup, package installs, vendor downloads and
  image configuration. Each workaround has a comment explaining why; keep that
  convention for new ones.
- `system_files/`: copied over `/` at build time (repo files, systemd units,
  dconf, udev, kargs, Flatpak preinstall list).
- `ci/build-image.sh [--rechunk]`: the build CI runs; works locally too.
- `disk_config/`: bootc-image-builder configs (ISO, qcow2); used by the manual
  `build-disk.yml` workflow.
- `image-template.env`: image name, org, labels.

## Build rules

- Install with `dnf5`; vendor RPMs whose `%post` needs a running system go in
  with `--setopt=tsflags=noscripts`, then redo the needed steps explicitly.
- Nothing under `/var` carries into a deployed system. Put files in `/usr` or
  `/etc`, or use a first-boot systemd unit.
- GitHub release lookups use `gh_latest_release` (authenticated via the
  `gh_token` build secret). Every `curl --retry` also passes `--retry-all-errors`.
- Verify vendor downloads (signature or checksum) where the vendor publishes one,
  as the existing entries do.
- New Flatpak: add a `[Flatpak Preinstall <app-id>]` entry to
  `system_files/etc/flatpak/preinstall.d/laptop-image.preinstall`. Apps come only
  from Flathub.
- No snapd, no dkms/out-of-tree modules (see `build.sh`). Dotfiles, hugo and
  IDrive are deliberately not in the image.
- Update the README's "What's in the image" when adding or removing software.

## Local build

```sh
GITHUB_TOKEN=$(gh auth token) ci/build-image.sh
```

Booting a local build needs it in root's storage (`sudo podman build ...` or
`podman image scp`), then
`sudo bootc switch --transport containers-storage localhost/laptop-image:latest`.
Don't switch the running laptop to a local build unless asked.

## Secrets

`cosign.key` is gitignored and must never be committed; the signing key lives
in the `SIGNING_SECRET` repository secret. `cosign.pub` is the public key.

## Related repos

- `opsrob/dotfiles` (chezmoi): user config, including the `opsrob-logs` /
  `dontcall-logs` scripts that the `cloudfront-logs-pull@.timer` units here run.
