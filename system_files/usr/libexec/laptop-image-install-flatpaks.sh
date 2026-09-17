#!/bin/bash
# Installs the default Flatpaks this image expects, on first boot only
# (guarded by the systemd unit's ConditionPathExists on the stamp file
# below). Can't run at container build time: `flatpak install --system`
# writes to /var/lib/flatpak, and /var isn't part of the ostree/bootc image
# commit - only /usr and /etc are. A build-time install "succeeds" but is
# silently discarded on deploy (confirmed 2026-09-17: CI logged a clean
# install, but none of the apps were present after `bootc upgrade` +
# reboot).
set -oue pipefail

STAMP=/var/lib/laptop-image/flatpaks-installed

flatpak install --system -y flathub \
    org.zotero.Zotero \
    org.signal.Signal \
    com.vivaldi.Vivaldi \
    md.obsidian.Obsidian \
    tv.plex.PlexDesktop

mkdir -p "$(dirname "$STAMP")"
touch "$STAMP"
