#!/bin/bash
set -euo pipefail

if [[ -z "${SRCROOT:-}" || -z "${BUILD_DIR:-}" || -z "${CONFIGURATION:-}" ]]; then
  echo "Skipping CocoaPods prebuild because required Xcode environment is missing."
  exit 0
fi

workspace_path="${SRCROOT}/Runner.xcworkspace"
if [[ ! -d "${workspace_path}" ]]; then
  echo "Expected workspace at ${workspace_path}" >&2
  exit 1
fi

derived_data_path="$(dirname "$(dirname "${BUILD_DIR}")")"
platform_suffix="${EFFECTIVE_PLATFORM_NAME:-}"
configuration_dir="${BUILD_DIR}/${CONFIGURATION}${platform_suffix}"
sdk_name="${PLATFORM_NAME:-iphonesimulator}"

build_pod_scheme() {
  local scheme="$1"
  local marker="$2"

  if [[ -d "${marker}" ]]; then
    return
  fi

  echo "Prebuilding ${scheme} for project-based xcodebuild verification..."
  local -a clean_env
  clean_env=(
    env
    -i
    PATH="${PATH}"
    HOME="${HOME}"
    LANG="${LANG:-en_US.UTF-8}"
    TMPDIR="${TMPDIR:-/tmp}"
  )

  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    clean_env+=(DEVELOPER_DIR="${DEVELOPER_DIR}")
  fi

  "${clean_env[@]}" \
    xcodebuild \
    -workspace "${workspace_path}" \
    -scheme "${scheme}" \
    -configuration "${CONFIGURATION}" \
    -sdk "${sdk_name}" \
    -derivedDataPath "${derived_data_path}" \
    build
}

build_pod_scheme "Pods-Runner" "${configuration_dir}/Pods_Runner.framework"
build_pod_scheme "Pods-RunnerTests" "${configuration_dir}/Pods_RunnerTests.framework"
