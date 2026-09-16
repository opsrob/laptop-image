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

# kernel-headers/dkms are deliberately NOT ported here yet - see the laptop
# bootc migration plan (~/.claude/plans/what-are-folk-using-zazzy-diffie.md,
# Step 2B): dkms needs out-of-tree kernel modules rebuilt against the exact
# deployed kernel, which is a different problem on an image-based system
# than on a regular mutable install (Bluefin/ublue handle their own akmods
# this way already - follow that pattern if a dkms module is actually
# needed here, don't just dnf5 install dkms and hope).

# snapd (classic-confinement snaps): VM-verified 2026-09-15 that snapd
# itself wasn't installed in the image at all, hence no /var/lib/snapd, no
# /snap, no /snap/bin on PATH. Resolves fine from Fedora's own repo (not
# negativo17). The /snap symlink is the same manual step the old Ansible
# task needed (tasks/packages.yml) - Fedora's snapd package doesn't create
# it automatically. Still unverified: whether the actual snap list
# (zotero-snap, signal-desktop, vivaldi, libation, hugo from the extended
# channel, and the classic ones - obsidian, ghostty, plex-desktop) installs
# and runs correctly on this ostree base - test that in the next VM build.
dnf5 install -y --skip-unavailable snapd
ln -sf /var/lib/snapd/snap /snap
systemctl enable snapd.socket

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

# /usr/local isn't usable at build time on this image (almost certainly
# symlinked into /var for runtime mutability, which doesn't exist yet
# mid-build) - both tools default there and need pointing at /usr
# instead.
#
# pip: "OSError: No such file or directory: '/usr/local/lib'" without
# --prefix=/usr. --break-system-packages: Fedora's system pip otherwise
# refuses unmanaged installs (PEP 668).
pip install --break-system-packages --prefix=/usr 'dnspython>=1.16.0' virtualenv

# npm: "ENOTDIR: not a directory, mkdir '/usr/local'" without --prefix=/usr.
npm install -g --prefix=/usr aws-cdk

### tflint - the old Ansible task's install script
### (raw.githubusercontent.com/.../install_linux.sh) 404s now, upstream
### removed it; confirmed via `curl -fsSL` (which silently no-ops on a
### 404 rather than erroring the build - that's why the previous version
### of this line "succeeded" without actually installing anything).
### Download the release zip directly instead, same pattern as Proton
### Bridge/zoom/ente above.
TFLINT_URL=$(curl -fsSL https://api.github.com/repos/terraform-linters/tflint/releases/latest \
    | grep -o '"browser_download_url": *"[^"]*tflint_linux_amd64\.zip"' \
    | cut -d'"' -f4)
curl -fsSL -o /tmp/tflint.zip "${TFLINT_URL}"
unzip -o /tmp/tflint.zip -d /usr/bin tflint
rm /tmp/tflint.zip

### aws-cli - the old Ansible task's `install.sh | bash -s -- --system`
### only supports two install modes: --system (hardcoded to
### /usr/local/aws-cli + /usr/local/bin, unusable at build time, same class
### of problem pip/npm hit above) or a user-local XDG install (also wrong -
### no real $HOME at build time). Neither works here. Use the zip-based
### installer directly instead, which accepts explicit --install-dir/
### --bin-dir, redirected to /usr like the pip/npm fixes above.
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --install-dir /usr/aws-cli --bin-dir /usr/bin
rm -rf /tmp/awscliv2.zip /tmp/aws

### OpenTofu - installs via the official script's --install-method rpm,
### which drops a yum repo and dnf-installs the `tofu` package (goes
### through the normal package manager, so no /usr/local-style path
### problem like aws-cli above).
curl -fsSL https://get.opentofu.org/install-opentofu.sh \
    | sh -s -- --install-method rpm

### VM-verified 2026-09-15: the sslcacert bug the old Ansible task worked
### around does reproduce here - the repo file points at
### /etc/pki/tls/certs/ca-bundle.crt, which doesn't exist/work on Fedora,
### breaking dnf5 metadata refresh ("Problem with the SSL CA cert"). Both
### [opentofu] and [opentofu-source] sections need the same corrected
### value, so a plain sed (which touches every matching line) works fine
### here - unlike the old lineinfile task, which only rewrote the last
### match and needed ini_file to handle both sections independently.
sed -i 's#^sslcacert=.*#sslcacert=/etc/ssl/certs/ca-bundle.crt#' /etc/yum.repos.d/opentofu.repo

### opentofu.repo's two sections (opentofu, opentofu-source) both ship
### with repo_gpgcheck=1 and a remote gpgkey= URL. The install script
### above imports these keys during the build's own dnf5 transaction, but
### that trust is tracked under /var, which doesn't survive from the
### image build into a deployed ostree/bootc system - VM-tested
### 2026-09-16: rpm --import'ing both keys at build time (see git
### history) does NOT fix this, dnf5 still prompts to re-import on every
### fresh deployment. Package-level gpgcheck=1 (untouched) still verifies
### each RPM's own signature at install time, which is the check that
### actually matters; disabling the separate, weaker repo metadata check
### is what actually stops the prompt, same fix as HashiCorp's repo file.
sed -i 's/^repo_gpgcheck=.*/repo_gpgcheck=0/' /etc/yum.repos.d/opentofu.repo

### Plymouth theme
plymouth-set-default-theme details -R

#### Example for enabling a System Unit File

systemctl enable podman.socket
systemctl enable crond
