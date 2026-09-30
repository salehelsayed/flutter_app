#!/bin/bash
# Repair the appium-qa MCP stack for a physical iPhone.
#
# Three independent host-side faults break real-device Appium sessions on
# Xcode 27 / macOS 26 / iOS 26. This script repairs the two that are safe to
# automate and reports on the third.
#
#  1. node-devicectl (bundled under appium-xcuitest-driver) builds the process
#     filter `executable.path BEGINSWITH "<app path>"`. Xcode 27's devicectl
#     rejects that field with CoreDeviceError 28001 ("Did you mean 'Executable
#     Path'?"). The accepted identifier is `executablePath`. Without the fix,
#     WebDriverAgent process lookup and termination always fail. Re-run this
#     script after any appium-qa runtime reinstall or upgrade -- npm restores
#     the unpatched file.
#
#  2. A WebDriverAgent already installed on the phone keeps the
#     application-identifier entitlement it was signed with. Switching between
#     appium_prepare_ios_real_device (wildcard profile, 397R9Q4WMX.*) and the
#     xcodebuild startup strategy (explicit id) makes iOS refuse the upgrade:
#     "Upgrade's application-identifier entitlement string ... does not match
#     installed application's ...; rejecting upgrade", surfacing as
#     "xcodebuild failed with code 65". Removing the installed runner clears it.
#
#  3. Appium's own RemoteXPC tunnel is a separate service that is not running
#     here ("Tunnel registry port not found"). Without it the
#     `appium:usePreinstalledWDA` path cannot launch or reach WebDriverAgent.
#     Use the xcodebuild startup strategy instead -- see USAGE below.
#
# USAGE
#   bash docker-ws/repair_appium_ios_real_device.sh [--udid <udid>] [--keep-wda]
#
# Working session capabilities for a real iPhone (no usePreinstalledWDA):
#   appium:udid                 <udid>
#   appium:xcodeOrgId           397R9Q4WMX
#   appium:xcodeSigningId       Apple Development
#   appium:updatedWDABundleId   com.facebook.WebDriverAgentRunner
#   appium:wdaLaunchTimeout     420000        # the first build is slow
set -u

UDID="00008030-001A6D2801BB802E"
KEEP_WDA=0
WDA_BUNDLE_ID="com.facebook.WebDriverAgentRunner.xctrunner"
RUNTIME_ROOT="${APPIUM_QA_RUNTIME_ROOT:-$HOME/.local/share/appium-qa}"

while [ $# -gt 0 ]; do
  case "$1" in
    --udid) UDID="$2"; shift 2 ;;
    --keep-wda) KEEP_WDA=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

echo "=== 1. node-devicectl process filter (Xcode 27 field name) ==="
patched=0
seen=0
while IFS= read -r f; do
  seen=$((seen + 1))
  if grep -q 'executable\.path BEGINSWITH' "$f"; then
    [ -f "$f.pre-xcode27.bak" ] || cp "$f" "$f.pre-xcode27.bak"
    /usr/bin/sed -i '' 's/executable\.path BEGINSWITH/executablePath BEGINSWITH/g' "$f"
    echo "patched   $f"
    patched=$((patched + 1))
  else
    echo "already   $f"
  fi
done < <(grep -rlE --include='*.js' --include='*.cjs' --include='*.mjs' \
  'executable(\.)?[Pp]ath BEGINSWITH' "$RUNTIME_ROOT" 2>/dev/null)
echo "files-seen=$seen files-patched=$patched"
if [ "$seen" -eq 0 ]; then
  echo "WARNING: no node-devicectl process filter found under $RUNTIME_ROOT" >&2
fi

echo
echo "=== 2. stale WebDriverAgent install on $UDID ==="
if [ "$KEEP_WDA" -eq 1 ]; then
  echo "skipped (--keep-wda)"
else
  if xcrun devicectl device info apps --device "$UDID" --quiet -j - 2>/dev/null \
      | grep -q "$WDA_BUNDLE_ID"; then
    xcrun devicectl device uninstall app --device "$UDID" "$WDA_BUNDLE_ID" 2>&1 | tail -3
  else
    echo "not installed; nothing to remove"
  fi
fi

echo
echo "=== 3. Appium RemoteXPC tunnel ==="
if pgrep -f '(tunnel.*xcuitest|appium.*tunnel)' >/dev/null 2>&1; then
  echo "a tunnel process is running"
else
  echo "no Appium RemoteXPC tunnel is running."
  echo "Do NOT pass appium:usePreinstalledWDA / appium:prebuiltWDAPath;"
  echo "use the xcodebuild startup strategy capabilities listed at the top of this script."
fi
