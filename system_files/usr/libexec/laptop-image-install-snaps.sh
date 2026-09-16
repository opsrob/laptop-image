#!/bin/bash
# Installs the snap packages this image expects, on first boot only (guarded
# by the systemd unit's ConditionPathExists on the stamp file below). Can't
# run at container build time: snap install needs a live snapd daemon, which
# doesn't exist inside `podman build` (no systemd/D-Bus there).
set -oue pipefail

STAMP=/var/lib/laptop-image/snaps-installed

snap wait system seed.loaded

snap install zotero-snap signal-desktop vivaldi libation
snap install hugo --channel=extended/stable
snap install obsidian ghostty plex-desktop --classic

mkdir -p "$(dirname "$STAMP")"
touch "$STAMP"
