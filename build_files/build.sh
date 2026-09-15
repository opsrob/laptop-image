#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
# (includes the yum.repos.d/*.repo files for vscode/1password/hashicorp/google-chrome)
cp -avf "/ctx/system_files"/. /

### Repo/key setup not covered by a plain .repo file in system_files/

# Bluefin uses the "negativo17" multimedia repo for codecs/drivers rather
# than RPM Fusion (confirmed from the actual build log - RPM Fusion is not
# among the repos this base image has enabled), unlike Bazzite/Aurora which
# is what the template's boilerplate comment above assumed. Don't add RPM
# Fusion here on the assumption its packages are needed - check what
# negativo17 already provides before adding anything from it explicitly.

# ProtonVPN publishes its repo config via a release RPM rather than a plain
# .repo file; --nogpgcheck matches the original Ansible task, which also
# disabled gpg check for this install.
dnf5 install -y --nogpgcheck \
    'https://repo.protonvpn.com/fedora-44-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.4-1.noarch.rpm'

# Proton Mail Bridge is installed from a one-off release asset (not a
# persistent repo), so its signing key needs importing explicitly first.
rpm --import https://proton.me/download/bridge/bridge_pubkey.gpg

### Install packages

# --skip-unavailable: Bluefin already ships several of these (and pulls
# more in transitively via @development-tools), and dnf5 hard-fails the
# *entire* transaction if any requested package is already installed -
# skip-unavailable makes it tolerate that instead of aborting everything.
#
# libva-intel-driver (the legacy "i965" VAAPI driver, RPM Fusion's
# packaging of intel/intel-vaapi-driver) intentionally dropped, not just
# renamed: this laptop is a Framework 12th Gen Intel (Alder Lake, Iris Xe
# graphics), and i965 only really targets Gen4-Gen7 hardware - Intel
# deprecated it in favor of the iHD driver for Broadwell/Gen8+. Per rob:
# it was likely leftover from past troubleshooting, not something that
# was actually needed on this hardware. It also doesn't exist under that
# name on Bluefin's negativo17-based repo set anyway (build failure: "No
# match for argument").
#
# The correct modern driver for this hardware is the iHD one, packaged on
# Fedora/RPM Fusion as libva-intel-media-driver (upstream/other distros
# call it "intel-media-driver" - that exact name doesn't exist on
# Fedora). Included below; --skip-unavailable means this is a no-op if
# Bluefin's own build already provides equivalent hardware video
# acceleration, which is plausible for a media/gaming-focused image -
# confirm which is true in the VM test (Step 4 of the migration plan) via
# `vainfo`.
#
# --skip-unavailable (applies to the whole list below): Bluefin already
# ships several of these (and pulls more in transitively via
# @development-tools), and dnf5 hard-fails the *entire* transaction if
# any requested package is already installed - skip-unavailable makes it
# tolerate that instead of aborting everything.
dnf5 install -y --skip-unavailable \
    libva-intel-media-driver \
    thunderbird \
    pykickstart \
    '@development-tools' \
    python3-pip \
    python3-psutil \
    code \
    gimp \
    1password \
    dnf-plugins-core \
    terraform \
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

# proton-vpn-gnome-desktop pulls in proton-vpn-daemon, whose %posttrans
# scriptlet tries to reach a live D-Bus system bus (only after already
# successfully creating its systemd unit symlink) - there's no bus in a
# container build, so it exits non-zero. RPM itself calls this
# "Non-critical" and keeps going, but dnf5 treats it as fatal to the
# *whole* transaction regardless (confirmed: build failed here after
# successfully installing 788/789 other packages). Install this one
# separately with scripts disabled, then redo the one thing its %post
# actually needed to accomplish (the unit enable, which had already
# succeeded before the scriptlet died) explicitly.
dnf5 install -y --skip-unavailable --setopt=tsflags=noscripts \
    proton-vpn-gnome-desktop
systemctl enable me.proton.vpn.split_tunneling.service

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
# app now, not the old CLI/idrivecron setup). Same class of problem as
# proton-vpn-daemon above: its %post scriptlet does `mkdir /home` while
# installing file-manager icon integration, assuming /home is a plain
# missing directory - on this ostree-based image /home is a symlink (to
# /var/home), so mkdir fails ("File exists") and dnf5 aborts the whole
# transaction over what RPM itself calls a non-critical, purely cosmetic
# failure (the log confirms it wasn't even going to do anything: "Dolphin
# file manager not detected. Skipping plugin installation"). noscripts
# sidesteps it; nothing here needs redoing manually, unlike proton-vpn.
dnf5 install -y --nogpgcheck --setopt=tsflags=noscripts \
    'https://www.idrivedownloads.com/downloads/linux/linux-desktop/IDriveForLinux.rpm'

# Zoom and Ente Photos both ship as self-contained, unsigned release RPMs
# rather than through any yum repo - a bare `dnf5 install -y zoom`/`ente`
# doesn't resolve to anything (confirmed via `dnf5 repoquery` against every
# repo this image configures - both were only ever present on the old
# laptop from a one-off manual install `dnf install <downloaded-rpm>`,
# which the old Ansible task's `state: present` silently no-op'd on ever
# since instead of actually being able to reinstall from scratch).
#
# noscripts applied preemptively on both: two other vendor desktop-app
# RPMs installed this way (proton-vpn-daemon, idriveforlinux) already hit
# the exact same failure class - a %post/%posttrans scriptlet assuming a
# live desktop/systemd environment (desktop database/icon cache updates,
# D-Bus calls) that doesn't exist in a container build, which RPM itself
# treats as non-critical but dnf5 treats as fatal to the whole
# transaction. If either actually needs a real postinstall step, this VM
# test (Step 4 of the migration plan) will surface it as a missing
# icon/mime association, not a build failure to debug blind.
dnf5 install -y --nogpgcheck --setopt=tsflags=noscripts \
    'https://zoom.us/client/latest/zoom_x86_64.rpm'

ENTE_URL=$(curl -fsSL https://api.github.com/repos/ente/photos-desktop/releases/latest \
    | grep -o '"browser_download_url": *"[^"]*x86_64\.rpm"' \
    | head -1 \
    | cut -d'"' -f4)
dnf5 install -y --nogpgcheck --setopt=tsflags=noscripts "${ENTE_URL}"

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
