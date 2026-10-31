#!/bin/bash
# Verify a signed SE-41 version file with the app's own k1 public key (read from the source), then print its payload.
#   host-run bash docker-ws/se41_verify.sh <signed file relative to the repo>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 2
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/bin:/bin"
K1=$(sed -n "/updateCheckK1PublicKeyBase64 =/{n;s/.*'\(.*\)'.*/\1/p;}" lib/features/update_check/domain/update_check_keys.dart)
[ ${#K1} -ge 40 ] || { echo "k1 public key not found"; exit 3; }
dart run tool/sign_version_file.dart verify --pub "$K1" --in "${1:?file}"; rc=$?
echo "verify_exit=$rc sha256=$(shasum -a 256 "$1" | cut -c1-64)"
exit $rc
