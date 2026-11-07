#!/bin/bash
# Sets the default power profile to "performance" on first
# boot only (guarded by the systemd unit's ConditionPathExists on the stamp
# file below). Can't do this at container build time: it
# talks to the live system D-Bus (tuned-ppd), which doesn't exist in a
# container build - same class of problem as proton-vpn-daemon in
# build.sh. tuned-ppd persists whatever profile is set here and restores
# it on every subsequent boot, so this only needs to run once - a user who
# later changes it in Settings stays changed.
set -oue pipefail

STAMP=/var/lib/laptop-image/power-profile-set

# Fedora uses tuned-ppd, which implements the power-profiles-daemon D-Bus
# API but doesn't ship the powerprofilesctl client (this failed with exit
# 127 on Bluefin too), so set the property over D-Bus directly.
busctl set-property org.freedesktop.UPower.PowerProfiles \
    /org/freedesktop/UPower/PowerProfiles \
    org.freedesktop.UPower.PowerProfiles ActiveProfile s performance

mkdir -p "$(dirname "$STAMP")"
touch "$STAMP"
