# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base Image
# Fedora Silverblue (moved off Bluefin 2026-11: ublue-os/bluefin became the
# volunteer-run "Bluefin Classic" and lags Fedora releases - see
# https://github.com/ublue-os/bluefin/discussions/4951). Anything Bluefin
# provided that this laptop needs is now added explicitly in build.sh.
FROM quay.io/fedora/fedora-silverblue:45@sha256:a9d48e07aa5f4ce4265d9eb7ac91b615e36c51eb82018c0d6cf38eb1eb65e005
## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:stable
# FROM ghcr.io/ublue-os/aurora:stable
# FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable
#
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:44
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.
##
## Needed here: build failed with "mkdir failed - File exists" unpacking
## google-chrome-stable and 1password specifically - the two packages this
## comment names as examples.

RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=gh_token,required=false \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
