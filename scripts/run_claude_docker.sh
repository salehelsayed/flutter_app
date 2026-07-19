#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="${CLAUDE_DOCKER_IMAGE:-claude-code-local}"
CLAUDE_DOCKER_HOME="${CLAUDE_DOCKER_HOME:-${HOME}/.claude-docker-home}"
HOST_ANDROID_DEBUG_KEYSTORE="${CLAUDE_DOCKER_ANDROID_DEBUG_KEYSTORE:-${HOME}/.android/debug.keystore}"
HOST_BRIDGE_SCRIPT="${REPO_ROOT}/scripts/claude_host_tool_bridge.py"
HOST_BIN_DIR="${CLAUDE_DOCKER_HOME}/host-bin"
HOST_TMP_DIR="${REPO_ROOT}/.claude-host-tmp"
HOST_BRIDGE_PID=""
HOST_BRIDGE_PORT=""
HOST_BRIDGE_TOKEN=""
CONTAINER_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
HOST_TOOL_SHIMS=(
  flutter
  dart
  xcrun
  xcodebuild
  pod
  adb
  ios-deploy
  idevice_id
  ideviceinstaller
)

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

prepare_android_debug_keystore() {
  local dest="${CLAUDE_DOCKER_HOME}/.android/debug.keystore"

  if [ "${CLAUDE_DOCKER_MOUNT_ANDROID_DEBUG_KEYSTORE:-1}" = "0" ]; then
    return 0
  fi
  if [ ! -f "${HOST_ANDROID_DEBUG_KEYSTORE}" ]; then
    return 0
  fi
  if [ "${HOST_ANDROID_DEBUG_KEYSTORE}" = "${dest}" ]; then
    return 0
  fi

  mkdir -p "${CLAUDE_DOCKER_HOME}/.android"
  # Docker Desktop cannot reliably file-bind-mount into /claude-home because
  # /claude-home is itself a bind mount.  Sync the one debug keystore into the
  # mounted Claude home instead; inside the container it still appears at the
  # Android default path: /claude-home/.android/debug.keystore.
  if [ -L "${dest}" ]; then
    rm -f "${dest}"
  fi
  if [ -e "${dest}" ] && [ ! -f "${dest}" ]; then
    rm -rf "${dest}"
  fi
  if [ ! -f "${dest}" ] || ! cmp -s "${HOST_ANDROID_DEBUG_KEYSTORE}" "${dest}"; then
    cp -p "${HOST_ANDROID_DEBUG_KEYSTORE}" "${dest}"
  fi
}

write_host_tool_shims() {
  local tool

  mkdir -p "${HOST_BIN_DIR}" "${HOST_TMP_DIR}"

  cat >"${HOST_BIN_DIR}/host-run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec python3 /workspace/scripts/claude_host_tool_bridge.py client "$@"
EOF
  chmod +x "${HOST_BIN_DIR}/host-run"

  for tool in "${HOST_TOOL_SHIMS[@]}"; do
    cat >"${HOST_BIN_DIR}/${tool}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec python3 /workspace/scripts/claude_host_tool_bridge.py client "${tool}" "\$@"
EOF
    chmod +x "${HOST_BIN_DIR}/${tool}"
  done

  if [ "${CLAUDE_DOCKER_ENABLE_HOST_CLIPBOARD:-1}" != "0" ]; then
    write_clipboard_shims
  fi
}

write_clipboard_shims() {
  cat >"${HOST_BIN_DIR}/.clipboard-shim-lib" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

container_root="${CLAUDE_CONTAINER_REPO_ROOT:-/workspace}"
shared_root="${container_root}/.claude-host-tmp"
helper="${container_root}/scripts/claude_macos_clipboard.py"
host_run="/claude-host-bin/host-run"
mkdir -p "${shared_root}"

clipboard_tmp() {
  printf '%s/clipboard-%s-%s-%s' "${shared_root}" "${1:-data}" "$$" "${RANDOM:-0}"
}

clipboard_image_stdout() {
  local tmp
  tmp="$(clipboard_tmp image).png"
  "${host_run}" "${helper}" write-image "${tmp}" >/dev/null
  cat "${tmp}"
  rm -f "${tmp}"
}

clipboard_read_text() {
  exec "${host_run}" "${helper}" read-text
}

clipboard_write_text_stdin() {
  local tmp status
  tmp="$(clipboard_tmp text).txt"
  cat >"${tmp}"
  set +e
  "${host_run}" "${helper}" write-text-file "${tmp}" >/dev/null
  status="$?"
  set -e
  rm -f "${tmp}"
  exit "${status}"
}
EOF
  chmod +x "${HOST_BIN_DIR}/.clipboard-shim-lib"

  cat >"${HOST_BIN_DIR}/xclip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Minimal xclip emulation for Claude Code's Linux clipboard probes. It bridges
# macOS clipboard text/images from the host into the Docker container.
# shellcheck disable=SC1091
source /claude-host-bin/.clipboard-shim-lib

target=""
output=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|-out)
      output=1
      shift
      ;;
    -i|-in)
      output=0
      shift
      ;;
    -t|-target)
      target="${2:-}"
      shift 2
      ;;
    -selection|-sel|-display)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ "${output}" = "1" ]; then
  case "${target:-}" in
    TARGETS)
      exec "${host_run}" "${helper}" targets
      ;;
    image/*)
      clipboard_image_stdout
      exit 0
      ;;
    ""|text/*|UTF8_STRING|STRING|TEXT)
      clipboard_read_text
      ;;
    *)
      exit 1
      ;;
  esac
fi

clipboard_write_text_stdin
EOF
  chmod +x "${HOST_BIN_DIR}/xclip"

  cat >"${HOST_BIN_DIR}/wl-paste" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Minimal wl-paste emulation for image/text reads from the macOS host clipboard.
# shellcheck disable=SC1091
source /claude-host-bin/.clipboard-shim-lib

target="text/plain"
list_types=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -l|--list-types)
      list_types=1
      shift
      ;;
    --type)
      target="${2:-}"
      shift 2
      ;;
    --type=*)
      target="${1#--type=}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ "${list_types}" = "1" ]; then
  exec "${host_run}" "${helper}" targets
fi

case "${target}" in
  image/*)
    clipboard_image_stdout
    ;;
  *)
    clipboard_read_text
    ;;
esac
EOF
  chmod +x "${HOST_BIN_DIR}/wl-paste"

  cat >"${HOST_BIN_DIR}/wl-copy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source /claude-host-bin/.clipboard-shim-lib
clipboard_write_text_stdin
EOF
  chmod +x "${HOST_BIN_DIR}/wl-copy"

  cat >"${HOST_BIN_DIR}/xsel" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source /claude-host-bin/.clipboard-shim-lib

output=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output)
      output=1
      shift
      ;;
    -i|--input)
      output=0
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ "${output}" = "1" ]; then
  clipboard_read_text
fi

clipboard_write_text_stdin
EOF
  chmod +x "${HOST_BIN_DIR}/xsel"

  cat >"${HOST_BIN_DIR}/pbpaste" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source /claude-host-bin/.clipboard-shim-lib
clipboard_read_text
EOF
  chmod +x "${HOST_BIN_DIR}/pbpaste"

  cat >"${HOST_BIN_DIR}/pbcopy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source /claude-host-bin/.clipboard-shim-lib
clipboard_write_text_stdin
EOF
  chmod +x "${HOST_BIN_DIR}/pbcopy"
}

pick_free_port() {
  python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

random_bridge_token() {
  python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
}

wait_for_host_bridge() {
  local health_url="http://127.0.0.1:${HOST_BRIDGE_PORT}/health"
  local attempt

  for attempt in $(seq 1 50); do
    if python3 - "${health_url}" <<'PY' >/dev/null 2>&1; then
import json
import sys
import urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=0.5) as response:
    payload = json.loads(response.read().decode("utf-8"))
    if payload.get("ok") is not True:
        raise SystemExit(1)
PY
      return 0
    fi

    if ! kill -0 "${HOST_BRIDGE_PID}" >/dev/null 2>&1; then
      return 1
    fi
    sleep 0.1
  done

  return 1
}

cleanup_host_bridge() {
  if [ -n "${HOST_BRIDGE_PID}" ]; then
    kill "${HOST_BRIDGE_PID}" >/dev/null 2>&1 || true
    wait "${HOST_BRIDGE_PID}" >/dev/null 2>&1 || true
    HOST_BRIDGE_PID=""
  fi
}

start_host_bridge() {
  local bridge_log

  if [ "${CLAUDE_DOCKER_ENABLE_HOST_TOOLS:-1}" = "0" ]; then
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'Claude Docker host tools require python3 on the macOS host. Set CLAUDE_DOCKER_ENABLE_HOST_TOOLS=0 to disable.\n' >&2
    exit 1
  fi
  if [ ! -f "${HOST_BRIDGE_SCRIPT}" ]; then
    printf 'Missing host bridge script: %s\n' "${HOST_BRIDGE_SCRIPT}" >&2
    exit 1
  fi

  write_host_tool_shims
  HOST_BRIDGE_PORT="$(pick_free_port)"
  HOST_BRIDGE_TOKEN="$(random_bridge_token)"
  bridge_log="${CLAUDE_DOCKER_HOME}/host-bridge.log"
  : >"${bridge_log}"

  python3 "${HOST_BRIDGE_SCRIPT}" serve \
    --bind "${CLAUDE_DOCKER_HOST_BRIDGE_BIND:-127.0.0.1}" \
    --port "${HOST_BRIDGE_PORT}" \
    --token "${HOST_BRIDGE_TOKEN}" \
    --repo-root "${REPO_ROOT}" \
    --container-repo-root /workspace \
    >"${bridge_log}" 2>&1 &
  HOST_BRIDGE_PID="$!"
  trap cleanup_host_bridge EXIT INT TERM

  if ! wait_for_host_bridge; then
    printf 'Claude Docker host bridge failed to start. Log: %s\n' "${bridge_log}" >&2
    cat "${bridge_log}" >&2 || true
    cleanup_host_bridge
    exit 1
  fi

  DOCKER_RUN_ARGS+=(
    -e CLAUDE_HOST_BRIDGE_URL="http://${CLAUDE_DOCKER_HOST_BRIDGE_HOST:-host.docker.internal}:${HOST_BRIDGE_PORT}"
    -e CLAUDE_HOST_BRIDGE_TOKEN="${HOST_BRIDGE_TOKEN}"
    -e CLAUDE_CONTAINER_REPO_ROOT=/workspace
    -e CLAUDE_HOST_REPO_ROOT="${REPO_ROOT}"
    -v "${HOST_BIN_DIR}:/claude-host-bin:ro"
  )
  CONTAINER_PATH="/claude-host-bin:${CONTAINER_PATH}"
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
# installed from the Mac by syncing only the debug keystore into the mounted
# Claude home, not by mounting the whole ~/.android directory. Set
# CLAUDE_DOCKER_MOUNT_ANDROID_DEBUG_KEYSTORE=0 to skip this sync, or
# CLAUDE_DOCKER_ANDROID_DEBUG_KEYSTORE=/path/to/debug.keystore to provide a
# different keystore.
prepare_android_debug_keystore

DOCKER_RUN_ARGS+=(
  -e ANDROID_USER_HOME=/claude-home/.android
  -e GRADLE_USER_HOME=/claude-home/.gradle
)

if [ -z "${GRADLE_OPTS:-}" ]; then
  DOCKER_RUN_ARGS+=(-e GRADLE_OPTS=-Duser.home=/claude-home)
else
  DOCKER_RUN_ARGS+=(-e GRADLE_OPTS="${GRADLE_OPTS} -Duser.home=/claude-home")
fi

# Optional Linux-compatible SDK mounts. Do not point these at macOS Flutter or
# Android SDK installations; their host binaries cannot run in this Linux image.
# macOS Flutter/Xcode/iPhone access is provided by the host bridge shims below.
if [ -n "${CLAUDE_DOCKER_ANDROID_SDK:-}" ]; then
  DOCKER_RUN_ARGS+=(
    -e ANDROID_HOME=/opt/android-sdk
    -e ANDROID_SDK_ROOT=/opt/android-sdk
    -v "${CLAUDE_DOCKER_ANDROID_SDK}:/opt/android-sdk"
  )
  CONTAINER_PATH="/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:${CONTAINER_PATH}"
fi

if [ -n "${CLAUDE_DOCKER_FLUTTER_SDK:-}" ]; then
  DOCKER_RUN_ARGS+=(
    -e FLUTTER_ROOT=/opt/flutter
    -v "${CLAUDE_DOCKER_FLUTTER_SDK}:/opt/flutter"
  )
  CONTAINER_PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${CONTAINER_PATH}"
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
  docker run "${DOCKER_RUN_ARGS[@]}" -e PATH="${CONTAINER_PATH}" "${IMAGE_NAME}" claude --version
  exit 0
fi

# Normal launches retain Docker's cached layers.  Only the explicit update
# command rebuilds the npm-install layer.
docker build \
  -t "${IMAGE_NAME}" \
  -f "${REPO_ROOT}/docker/claude-code/Dockerfile" \
  "${REPO_ROOT}/docker/claude-code"

start_host_bridge

DOCKER_RUN_ARGS+=(
  -e PATH="${CONTAINER_PATH}"
  "${IMAGE_NAME}"
  claude
  "$@"
)

if [ -n "${HOST_BRIDGE_PID}" ]; then
  set +e
  docker run "${DOCKER_RUN_ARGS[@]}"
  status="$?"
  set -e
  cleanup_host_bridge
  exit "${status}"
fi

exec docker run "${DOCKER_RUN_ARGS[@]}"
