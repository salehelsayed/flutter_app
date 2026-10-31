#!/bin/bash
# Run Astra's 3 Group C focused flutter tests in build/wt-astra-c with the pinned SDK (call under with_native_lease.py).
set -uo pipefail
W="$(cd "$(dirname "$0")/.." && pwd)/build/wt-astra-c"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
cd "$W" || exit 3
rc=0
for t in test/features/contacts/contact_request_roundtrip_test.dart test/features/conversation/integration/camera_caption_relay_delivery_test.dart test/features/call/integration/muted_call_connection_decisions_test.dart; do
  echo "=== $t"; "$SDK/bin/flutter" test --no-pub --concurrency=1 --timeout=2m "$t"; r=$?; echo "=== rc=$r $t"; [ $r -ne 0 ] && rc=$r
done
exit $rc
