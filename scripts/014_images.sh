#!/bin/sh
# Container images: BUILD ONCE, DEPLOY EVERYWHERE (security rule S4, docs/CI_CD.md).
#
# Every image gets its version from its own source code:
#   projectcontrol-api:src-<12 chars>   = Git tree hash of deelproject1/backend
#   projectcontrol-web:src-<12 chars>   = Git tree hash of deelproject1/frontend
# Same source -> same version -> the image is never built twice. A change in only the
# frontend rebuilds only the web image. Test, acceptance and production pull the SAME image,
# by digest (repo@sha256:...); the images contain no environment settings at all, everything
# environment-specific is passed at runtime (environment variables, deploy/compose.<env>.yml).
#
# Actions (several can be combined, they run in this order of arguments):
#   versions        print API_TAG= and WEB_TAG= for the checked-out commit
#   ensure          per image: already in the registry -> nothing to do; otherwise build it,
#                   scan it with Trivy and push it (PUSH=0: build + scan only, e.g. fork PRs)
#   resolve         print API_IMAGE=<repo>@sha256:... and WEB_IMAGE=... (fails if not built)
#   scan-deployed   pull the resolved images and scan them again (new CVEs since the build)
#   tag <alias>     add an extra tag to both images without rebuilding (sha-<commit>, test, acc, prod)
#   build           local build only (tag 'local'), for trying a Dockerfile
#
# Environment: REGISTRY (default ghcr.io/team5-vanroey; 'docker login' first),
#              PUSH (default 1), TRIVY_VERSION (default 0.76.1), SOURCE_URL (image label)
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/014_images.sh versions
#   sh scripts/014_images.sh ensure tag sha-$(git rev-parse --short=7 HEAD)
#   sh scripts/014_images.sh resolve > images.env

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository." >&2; exit 1; }

[ $# -ge 1 ] || { echo "Usage: sh scripts/014_images.sh <versions|ensure|resolve|scan-deployed|tag <alias>|build> ..." >&2; exit 2; }
command -v docker >/dev/null 2>&1 || { echo "Docker is not installed." >&2; exit 1; }

registry=${REGISTRY:-ghcr.io/team5-vanroey}
push=${PUSH:-1}
trivy=${TRIVY_VERSION:-0.76.1}
source_url=${SOURCE_URL:-https://github.com/Team5-VanRoey/IT-Project-Van-Roey}
commit=$(git rev-parse HEAD)

# component <name>: sets dir, dockerfile, context, repo and tag for api or web
component() {
  case "$1" in
    api) dir=deelproject1/backend;  dockerfile=deelproject1/backend/ProjectControl.Api/Dockerfile ;;
    web) dir=deelproject1/frontend; dockerfile=deelproject1/frontend/Dockerfile ;;
  esac
  context=$dir
  repo="$registry/projectcontrol-$1"
  tree=$(git rev-parse "HEAD:$dir") || { echo "Cannot read $dir from Git." >&2; exit 1; }
  tag="src-$(printf '%s' "$tree" | cut -c1-12)"
}

exists() { docker buildx imagetools inspect "$1" >/dev/null 2>&1; }
digest() { docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}' 2>/dev/null; }

scan() {  # scan <local image>
  mkdir -p "$HOME/.cache/trivy"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$HOME/.cache/trivy:/root/.cache/" "aquasec/trivy:$trivy" \
    image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --no-progress "$1" \
    || { echo "HIGH/CRITICAL vulnerabilities in $1: update the base image or the package listed above." >&2; return 1; }
}

ensure() {
  for c in api web; do
    component "$c"
    if exists "$repo:$tag"; then
      echo "== $c: $repo:$tag already built (source unchanged) -> reused, not rebuilt"
      continue
    fi
    if [ -n "$(git status --porcelain -- "$dir")" ]; then
      echo "WARNING: $dir has uncommitted changes; the version only describes committed code." >&2
    fi
    echo "== $c: building $repo:$tag"
    docker build -t "$repo:$tag" -f "$dockerfile" \
      --label "org.opencontainers.image.source=$source_url" \
      --label "org.opencontainers.image.revision=$commit" \
      --label "org.opencontainers.image.version=$tag" \
      "$context" || { echo "FAILED: build $c" >&2; return 1; }
    echo "== $c: Trivy scan"
    scan "$repo:$tag" || return 1
    if [ "$push" = "1" ]; then
      docker push "$repo:$tag" || { echo "FAILED: push $c (logged in to $registry?)" >&2; return 1; }
    else
      echo "== $c: PUSH=0, not pushed"
    fi
  done
}

resolve() {
  for c in api web; do
    component "$c"
    d=$(digest "$repo:$tag")
    [ -n "$d" ] || { echo "$repo:$tag does not exist: CI has not built this version (yet)." >&2; return 1; }
    name=$(printf '%s' "$c" | tr 'a-z' 'A-Z')
    echo "${name}_IMAGE=$repo@$d"
    echo "${name}_TAG=$tag"
  done
}

scan_deployed() {
  for c in api web; do
    component "$c"
    ref="$repo@$(digest "$repo:$tag")"
    echo "== $c: scanning $ref"
    docker pull -q "$ref" >/dev/null || { echo "FAILED: pull $ref" >&2; return 1; }
    scan "$ref" || return 1
  done
}

tag_alias() {  # tag_alias <alias>
  for c in api web; do
    component "$c"
    ref="$repo@$(digest "$repo:$tag")"
    docker buildx imagetools create --prefer-index=false -t "$repo:$1" "$ref" >/dev/null || { echo "FAILED: tag $repo:$1" >&2; return 1; }
    echo "== $c: $repo:$1 -> $tag (no rebuild)"
  done
}

build_local() {
  for c in api web; do
    component "$c"
    docker build -t "projectcontrol-$c:local" -f "$dockerfile" "$context" || return 1
  done
}

while [ $# -gt 0 ]; do
  action=$1; shift
  case "$action" in
    versions)      for c in api web; do component "$c"; echo "$(printf '%s' "$c" | tr 'a-z' 'A-Z')_TAG=$tag"; done ;;
    ensure)        ensure || exit 1 ;;
    resolve)       resolve || exit 1 ;;
    scan-deployed) scan_deployed || exit 1 ;;
    tag)           [ -n "$1" ] || { echo "tag needs a name" >&2; exit 2; }; tag_alias "$1" || exit 1; shift ;;
    build)         build_local || exit 1 ;;
    *)             echo "Unknown action '$action'." >&2; exit 2 ;;
  esac
done
