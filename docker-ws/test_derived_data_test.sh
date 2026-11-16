#!/bin/bash
# Contract for docker-ws/test_derived_data.sh with fake xcodebuild and flutter.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '#!/bin/bash\n[ -z "${FAKE_XCODE_FAIL:-}" ] || { echo "xcode-select: error"; exit 1; }\necho "Xcode ${FAKE_XCODE:-26.0}"\n' >"$tmp/bin/xcodebuild"
printf '#!/bin/bash\n[ -z "${FAKE_FLUTTER_FAIL:-}" ] || { echo "flutter: error"; exit 1; }\necho "{\\"frameworkVersion\\": \\"${FAKE_FLUTTER:-3.47.2}\\"}"\n' >"$tmp/bin/flutter"
chmod +x "$tmp/bin/xcodebuild" "$tmp/bin/flutter"
export PATH="$tmp/bin:$PATH"
# shellcheck source=docker-ws/test_derived_data.sh
. "$here/test_derived_data.sh"
fail() { echo "FAIL: $1"; exit 1; }

dd="$tmp/dd-hetzner-test-ios-device-release"
prepare_test_derived_data "$dd" >/dev/null || fail 'first prepare failed'
mkdir -p "$dd/Build/Intermediates.noindex" && echo o >"$dd/Build/Intermediates.noindex/warm.o"

prepare_test_derived_data "$dd" >/dev/null || fail 'second prepare failed'
[ -f "$dd/Build/Intermediates.noindex/warm.o" ] || fail 'same Xcode and Flutter wiped the build state'

FAKE_XCODE=26.1 prepare_test_derived_data "$dd" >/dev/null || fail 'Xcode change prepare failed'
[ ! -e "$dd/Build/Intermediates.noindex/warm.o" ] || fail 'an Xcode change kept the old build state'
echo o >"$dd/warm.o"
FAKE_XCODE=26.1 FAKE_FLUTTER=3.48.0 prepare_test_derived_data "$dd" >/dev/null || fail 'Flutter change prepare failed'
[ ! -e "$dd/warm.o" ] || fail 'a Flutter change kept the old build state'

# A failed probe changes nothing and reports failure.
echo o >"$dd/warm.o"
if FAKE_XCODE=26.1 FAKE_FLUTTER=3.48.0 FAKE_XCODE_FAIL=1 prepare_test_derived_data "$dd" 2>/dev/null; then
  fail 'a failed xcodebuild probe reported success'
fi
[ -f "$dd/warm.o" ] || fail 'a failed xcodebuild probe wiped the folder'
if FAKE_XCODE=26.1 FAKE_FLUTTER=3.48.0 FAKE_FLUTTER_FAIL=1 prepare_test_derived_data "$dd" 2>/dev/null; then
  fail 'a failed flutter probe reported success'
fi
[ -f "$dd/warm.o" ] || fail 'a failed flutter probe wiped the folder'
FAKE_XCODE=26.1 FAKE_FLUTTER=3.48.0 prepare_test_derived_data "$dd" >/dev/null || fail 'recovered probes failed'
[ -f "$dd/warm.o" ] || fail 'recovered probes with the same toolchain wiped the folder'

# A folder that cannot be replaced reports failure.
locked="$tmp/locked"
mkdir -p "$locked/dd-hetzner-test-x" && echo o >"$locked/dd-hetzner-test-x/warm.o"
chmod 500 "$locked"
if prepare_test_derived_data "$locked/dd-hetzner-test-x" >/dev/null 2>&1; then
  chmod 700 "$locked"; fail 'a folder that could not be replaced reported success'
fi
chmod 700 "$locked"

other="$tmp/tmp-dd-store"
mkdir -p "$other" && echo keep >"$other/keep"
if prepare_test_derived_data "$other" 2>/dev/null; then fail 'a non dd-hetzner-test folder was accepted'; fi
[ -f "$other/keep" ] || fail 'a non dd-hetzner-test folder was touched'

echo 'TEST_DERIVED_DATA_CONTRACT_PASS'
