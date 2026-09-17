#!/bin/bash
# Sets the default power-profiles-daemon profile to "performance" on first
# boot only (guarded by the systemd unit's ConditionPathExists on the stamp
# file below). Can't do this at container build time: powerprofilesctl
# talks to the live system D-Bus (power-profiles-daemon), which doesn't
# exist in a container build - same class of problem as proton-vpn-daemon/
# idriveforlinux in build.sh. The daemon persists whatever profile is set
# here into /var/lib/power-profiles-daemon/state.ini itself and restores it
# on every subsequent boot, so this only needs to run once - a user who
# later changes it in Settings stays changed.
set -oue pipefail

STAMP=/var/lib/laptop-image/power-profile-set

powerprofilesctl set performance

mkdir -p "$(dirname "$STAMP")"
touch "$STAMP"
