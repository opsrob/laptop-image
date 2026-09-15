#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
# (includes the yum.repos.d/*.repo files for vscode/1password/hashicorp/google-chrome)
cp -avf "/ctx/system_files"/. /

### Repo/key setup not covered by a plain .repo file in system_files/

# RPM Fusion free/nonfree ship by default on ublue main images (per Bluefin's
# own build) - do not re-add it here.

# ProtonVPN publishes its repo config via a release RPM rather than a plain
# .repo file; --nogpgcheck matches the original Ansible task, which also
# disabled gpg check for this install.
dnf5 install -y --nogpgcheck \
    'https://repo.protonvpn.com/fedora-44-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.4-1.noarch.rpm'

# Proton Mail Bridge is installed from a one-off release asset (not a
# persistent repo), so its signing key needs importing explicitly first.
rpm --import https://proton.me/download/bridge/bridge_pubkey.gpg

### Install packages

dnf5 install -y \
    thunderbird \
    pykickstart \
    '@development-tools' \
    proton-vpn-gnome-desktop \
    python3-pip \
    python3-psutil \
    code \
    gimp \
    1password \
    dnf-plugins-core \
    terraform \
    libva-intel-driver \
    inxi \
    lshw \
    xrandr \
    arandr \
    goaccess \
    procinfo \
    lsscsi \
    hwinfo \
    hdparm \
    unetbootin \
    cronie \
    python3 \
    python3-devel \
    bookworm \
    pylint \
    perl \
    vlc \
    golang \
    qbittorrent \
    nodejs22 \
    nodejs22-npm \
    nm-connection-editor \
    abcde \
    lame \
    flac \
    python3-eyed3 \
    iftop \
    alien \
    7zip \
    audacity \
    easytag \
    gh \
    gnome-boxes \
    hddtemp \
    inkscape \
    java-25-openjdk-headless \
    linkdupes \
    mediawriter \
    nmap \
    unoconv \
    google-chrome-stable \
    chezmoi \
    age

# kernel-headers/dkms and snapd (classic-confinement snaps) are deliberately
# NOT ported here yet - see the laptop bootc migration plan
# (~/.claude/plans/what-are-folk-using-zazzy-diffie.md, Step 2B) for why both
# need VM verification before being trusted on an ostree/bootc image rather
# than a traditional Fedora Workstation install:
#   - dkms needs out-of-tree kernel modules rebuilt against the exact
#     deployed kernel, which is a different problem on an image-based system
#     than on a regular mutable install (Bluefin/ublue handle their own
#     akmods this way already - follow that pattern if a dkms module is
#     actually needed here, don't just dnf5 install dkms and hope).
#   - classic-confinement snapd support on ostree-based Fedora has a history
#     of friction (the /snap symlink hack in the old Ansible repo is
#     evidence of that). Test snapd + the actual snap list
#     (zotero-snap, signal-desktop, vivaldi, libation, hugo, obsidian,
#     ghostty, plex-desktop) in the VM build before adding it here.

# Proton Mail Bridge - install the latest release asset directly (same
# approach as the old Ansible task: look up the current release, install
# the matching x86_64 rpm).
PROTON_BRIDGE_URL=$(curl -fsSL https://api.github.com/repos/ProtonMail/proton-bridge/releases/latest \
    | grep -o '"browser_download_url": *"[^"]*x86_64\.rpm"' \
    | head -1 \
    | cut -d'"' -f4)
dnf5 install -y "${PROTON_BRIDGE_URL}"

# IDrive desktop app (per project notes, IDrive is managed via this desktop
# app now, not the old CLI/idrivecron setup)
dnf5 install -y --nogpgcheck 'https://www.idrivedownloads.com/downloads/linux/linux-desktop/IDriveForLinux.rpm'

# Zoom and Ente Photos both ship as self-contained, unsigned release RPMs
# rather than through any yum repo - a bare `dnf5 install -y zoom`/`ente`
# doesn't resolve to anything (confirmed via `dnf5 repoquery` against every
# repo this image configures - both were only ever present on the old
# laptop from a one-off manual install `dnf install <downloaded-rpm>`,
# which the old Ansible task's `state: present` silently no-op'd on ever
# since instead of actually being able to reinstall from scratch).
dnf5 install -y --nogpgcheck 'https://zoom.us/client/latest/zoom_x86_64.rpm'

ENTE_URL=$(curl -fsSL https://api.github.com/repos/ente/photos-desktop/releases/latest \
    | grep -o '"browser_download_url": *"[^"]*x86_64\.rpm"' \
    | head -1 \
    | cut -d'"' -f4)
dnf5 install -y --nogpgcheck "${ENTE_URL}"

### pip / npm installs

# Fedora's system pip refuses unmanaged installs (PEP 668) without this flag
pip install --break-system-packages 'dnspython>=1.16.0' virtualenv
npm install -g aws-cdk

### tflint (no packaged RPM - official install script, same as the old
### Ansible task)
TFLINT_INSTALL_PATH=/usr/local/bin \
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh)"

### Plymouth theme
plymouth-set-default-theme details -R

#### Example for enabling a System Unit File

systemctl enable podman.socket
systemctl enable crond
