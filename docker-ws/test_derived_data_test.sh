#!/bin/bash
# Contract for docker-ws/test_derived_data.sh with fake xcodebuild and flutter.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '#!/bin/bash\necho "Xcode ${FAKE_XCODE:-26.0}"\n' >"$tmp/bin/xcodebuild"
printf '#!/bin/bash\necho "{\\"frameworkVersion\\": \\"${FAKE_FLUTTER:-3.47.2}\\"}"\n' >"$tmp/bin/flutter"
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

other="$tmp/tmp-dd-store"
mkdir -p "$other" && echo keep >"$other/keep"
if prepare_test_derived_data "$other" 2>/dev/null; then fail 'a non dd-hetzner-test folder was accepted'; fi
[ -f "$other/keep" ] || fail 'a non dd-hetzner-test folder was touched'

echo 'TEST_DERIVED_DATA_CONTRACT_PASS'
