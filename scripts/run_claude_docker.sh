#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="${CLAUDE_DOCKER_IMAGE:-claude-code-local}"
CLAUDE_DOCKER_HOME="${CLAUDE_DOCKER_HOME:-${HOME}/.claude-docker-home}"
HOST_ANDROID_DEBUG_KEYSTORE="${CLAUDE_DOCKER_ANDROID_DEBUG_KEYSTORE:-${HOME}/.android/debug.keystore}"

mkdir -p "${CLAUDE_DOCKER_HOME}" "${CLAUDE_DOCKER_HOME}/.android"

is_image_update_request() {
  local argument

  # The shell alias supplies Claude options before the command, so the update
  # subcommand is not necessarily the first argument.
  for argument in "$@"; do
    case "${argument}" in
      update|upgrade)
        return 0
        ;;
    esac
  done

  return 1
}

DOCKER_RUN_ARGS=(--rm)
if [ -t 0 ] && [ -t 1 ]; then
  DOCKER_RUN_ARGS+=(-it)
fi

DOCKER_RUN_ARGS+=(
  --user "$(id -u):$(id -g)"
  -e HOME=/claude-home
  # Claude is installed into the image by root, while the CLI deliberately
  # runs as the host user. Updates therefore belong to the image build below,
  # not to Claude's in-container npm updater.
  -e DISABLE_AUTOUPDATER=1
  -e NO_COLOR="${NO_COLOR:-}"
  -v "${REPO_ROOT}:/workspace"
  -v "${CLAUDE_DOCKER_HOME}:/claude-home"
  -w /workspace
)

# Keep Android debug update-installs compatible with APKs that were already
# installed from the Mac by exposing only the debug keystore, not the whole
# ~/.android directory. Set CLAUDE_DOCKER_MOUNT_ANDROID_DEBUG_KEYSTORE=0 to opt
# out, or CLAUDE_DOCKER_ANDROID_DEBUG_KEYSTORE=/path/to/debug.keystore to
# provide a different keystore.
if [ "${CLAUDE_DOCKER_MOUNT_ANDROID_DEBUG_KEYSTORE:-1}" != "0" ] && [ -f "${HOST_ANDROID_DEBUG_KEYSTORE}" ]; then
  DOCKER_RUN_ARGS+=(
    -v "${HOST_ANDROID_DEBUG_KEYSTORE}:/claude-home/.android/debug.keystore:ro"
  )
fi

# Optional Linux-compatible SDK mounts. Do not point these at macOS Flutter or
# Android SDK installations; their host binaries cannot run in this Linux image.
if [ -n "${CLAUDE_DOCKER_ANDROID_SDK:-}" ]; then
  DOCKER_RUN_ARGS+=(
    -e ANDROID_HOME=/opt/android-sdk
    -e ANDROID_SDK_ROOT=/opt/android-sdk
    -v "${CLAUDE_DOCKER_ANDROID_SDK}:/opt/android-sdk"
  )
fi

if [ -n "${CLAUDE_DOCKER_FLUTTER_SDK:-}" ]; then
  DOCKER_RUN_ARGS+=(
    -e FLUTTER_ROOT=/opt/flutter
    -e PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    -v "${CLAUDE_DOCKER_FLUTTER_SDK}:/opt/flutter"
  )
fi

if is_image_update_request "$@"; then
  printf 'Updating Claude Code Docker image...\n'
  docker build \
    --pull \
    --no-cache \
    -t "${IMAGE_NAME}" \
    -f "${REPO_ROOT}/docker/claude-code/Dockerfile" \
    "${REPO_ROOT}/docker/claude-code"

  printf 'Updated Claude Code version: '
  docker run "${DOCKER_RUN_ARGS[@]}" "${IMAGE_NAME}" claude --version
  exit 0
fi

# Normal launches retain Docker's cached layers.  Only the explicit update
# command rebuilds the npm-install layer.
docker build \
  -t "${IMAGE_NAME}" \
  -f "${REPO_ROOT}/docker/claude-code/Dockerfile" \
  "${REPO_ROOT}/docker/claude-code"

DOCKER_RUN_ARGS+=(
  "${IMAGE_NAME}"
  claude
  "$@"
)

exec docker run "${DOCKER_RUN_ARGS[@]}"
