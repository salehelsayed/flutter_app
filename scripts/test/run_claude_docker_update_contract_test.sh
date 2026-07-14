#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="${ROOT_DIR}/scripts/run_claude_docker.sh"
DOCKERFILE="${ROOT_DIR}/docker/claude-code/Dockerfile"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fake_bin="${tmp_dir}/bin"
docker_log="${tmp_dir}/docker.log"
mkdir -p "${fake_bin}" "${tmp_dir}/claude-home"

grep -Fxq 'FROM node:22-bullseye' "${DOCKERFILE}" ||
  fail 'Claude Code image must use Node 22 or newer'
grep -Fxq 'RUN npm install -g @anthropic-ai/claude-code@latest' "${DOCKERFILE}" ||
  fail 'Claude Code image must resolve the latest package during an explicit update'

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '{' \
  '  printf "CALL\n"' \
  '  printf "ARG\t%s\n" "$@"' \
  '  printf "END\n"' \
  '} >>"${FAKE_DOCKER_LOG:?}"' \
  'if [ "${1:-}" = "run" ]; then' \
  '  printf "2.1.209\n"' \
  'fi' \
  >"${fake_bin}/docker"
chmod +x "${fake_bin}/docker"

run_runner() {
  PATH="${fake_bin}:${PATH}" \
    FAKE_DOCKER_LOG="${docker_log}" \
    CLAUDE_DOCKER_HOME="${tmp_dir}/claude-home" \
    CLAUDE_DOCKER_IMAGE="claude-code-test" \
    "${RUNNER}" "$@"
}

# The user's alias places global options before update.  The wrapper must
# rebuild the immutable image and never pass this command to Claude itself.
update_output="$(run_runner --dangerously-skip-permissions --permission-mode acceptEdits update)"
grep -Fq 'Updating Claude Code Docker image...' <<<"${update_output}" ||
  fail 'update did not report an image rebuild'
grep -Fq 'Updated Claude Code version: 2.1.209' <<<"${update_output}" ||
  fail 'update did not report the rebuilt image version'
grep -Fxq $'ARG\tbuild' "${docker_log}" || fail 'update did not build the image'
grep -Fxq $'ARG\t--pull' "${docker_log}" || fail 'update did not refresh the base image'
grep -Fxq $'ARG\t--no-cache' "${docker_log}" || fail 'update reused the npm install layer'
grep -Fxq $'ARG\trun' "${docker_log}" || fail 'update did not verify the rebuilt image'
grep -Fxq $'ARG\t--version' "${docker_log}" || fail 'update did not request the image version'
grep -Fxq $'ARG\tDISABLE_AUTOUPDATER=1' "${docker_log}" ||
  fail 'container launch did not disable the in-container auto-updater'
if grep -Fxq $'ARG\tupdate' "${docker_log}"; then
  fail 'update was forwarded to the root-owned in-container installation'
fi

: >"${docker_log}"
run_runner --permission-mode acceptEdits --version >/dev/null
grep -Fxq $'ARG\tbuild' "${docker_log}" || fail 'normal launch did not build the cached image'
if grep -Fxq $'ARG\t--pull' "${docker_log}" || grep -Fxq $'ARG\t--no-cache' "${docker_log}"; then
  fail 'normal launch unexpectedly bypassed the cheap cached build'
fi
grep -Fxq $'ARG\t--version' "${docker_log}" || fail 'normal CLI arguments were not forwarded'
grep -Fxq $'ARG\tDISABLE_AUTOUPDATER=1' "${docker_log}" ||
  fail 'normal launch did not disable the in-container auto-updater'

printf 'PASS: Claude Docker update contract\n'
