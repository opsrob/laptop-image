#!/usr/bin/env bash
# Build the laptop image with podman, optionally rechunk it, and tag it.
# Used by .github/workflows/build.yml; also works locally from the repo root.
#
#   ci/build-image.sh             build and tag
#   ci/build-image.sh --rechunk   build, rechunk with rpm-ostree, and tag
#
# Image name, tag and metadata come from image-template.env. If GITHUB_TOKEN
# is set, it's passed to the build as the gh_token secret so build.sh's
# api.github.com lookups aren't rate limited. In GitHub Actions, IMAGE_NAME
# and DEFAULT_TAG go to $GITHUB_ENV and the tag list (alias_tags) to
# $GITHUB_OUTPUT.
set -euo pipefail

cd "$(dirname "$0")/.."

rechunk=0
case "${1:-}" in
"") ;;
--rechunk) rechunk=1 ;;
*)
    echo "usage: $0 [--rechunk]" >&2
    exit 2
    ;;
esac

# shellcheck source=image-template.env
source image-template.env
image="${IMAGE_NAME,,}"
tag="${DEFAULT_TAG}"

set -x

### Build

build_args=(--pull=newer --tag "${image}:${tag}" --file Containerfile)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    build_args+=(--secret "id=gh_token,env=GITHUB_TOKEN")
fi

git_sha=""
if [[ -z "$(git status --porcelain)" ]]; then
    git_sha=$(git rev-parse --short HEAD)
    raw="https://raw.githubusercontent.com/${REPO_ORGANIZATION}/${IMAGE_NAME}/${git_sha}"
    build_args+=(
        --label "io.artifacthub.package.readme-url=${raw}/README.md"
        --label "org.opencontainers.image.documentation=${raw}/README.md"
        --label "org.opencontainers.image.source=https://github.com/${REPO_ORGANIZATION}/${IMAGE_NAME}/blob/${git_sha}/Containerfile"
        --label "org.opencontainers.image.url=https://github.com/${REPO_ORGANIZATION}/${IMAGE_NAME}/tree/${git_sha}"
        --label "org.opencontainers.image.version=${tag}.$(date +%Y%m%d)-${git_sha}"
    )
fi
build_args+=(
    --label "io.artifacthub.package.deprecated=false"
    --label "io.artifacthub.package.keywords=${IMAGE_KEYWORDS}"
    --label "io.artifacthub.package.license=Apache-2.0"
    --label "io.artifacthub.package.logo-url=${IMAGE_LOGO_URL}"
    --label "io.artifacthub.package.prerelease=false"
    --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    --label "org.opencontainers.image.description=${IMAGE_DESC}"
    --label "org.opencontainers.image.title=${IMAGE_NAME}"
    --label "org.opencontainers.image.vendor=${REPO_ORGANIZATION}"
)

podman build "${build_args[@]}" .

### Rechunk: rebuild the image as up to 127 content-based layers, so an
### update only downloads the layers that changed. Uses the rpm-ostree inside
### the image just built, writing the result back over the same tag.

if ((rechunk)); then
    graphroot=$(podman info --format '{{.Store.GraphRoot}}')
    podman run --rm --pull=never --privileged \
        --mount=type=image,src="${image}:${tag}",target=/rpm-ostree \
        --mount=type=bind,src="${graphroot}",target=/run/host-container-storage,rw \
        --mount=type=tmpfs,target=/run/rpm-ostree-storage \
        --entrypoint /usr/bin/rpm-ostree \
        "localhost/${image}:${tag}" \
        compose build-chunked-oci \
        --max-layers 127 \
        --format-version=2 \
        --bootc \
        --rootfs /rpm-ostree \
        --output "containers-storage:[overlay@/run/host-container-storage+/run/rpm-ostree-storage]localhost/${image}:${tag}"
fi

### Tag: latest, <date>, latest-<date>, plus -<sha> variants when the tree
### is clean.

date=$(date +%Y%m%d)
tags=("${tag}" "${date}" "${tag}-${date}")
if [[ -n "${git_sha}" ]]; then
    tags+=("${tag}-${git_sha}" "${tag}-${date}-${git_sha}" "${date}-${git_sha}")
fi
for t in "${tags[@]:1}"; do
    podman tag "${image}:${tag}" "${image}:${t}"
done

set +x

if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "IMAGE_NAME=${image}" >>"${GITHUB_ENV}"
    echo "DEFAULT_TAG=${tag}" >>"${GITHUB_ENV}"
fi
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "alias_tags=${tags[*]}" >>"${GITHUB_OUTPUT}"
fi
echo "Tagged ${image}: ${tags[*]}"
