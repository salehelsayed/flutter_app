#!/bin/bash
# Apply and commit Codex-UI's iOS diagnostic patch (its code, unchanged) in the Codex-UI worktree.
#   host-run bash docker-ws/cui_wt_diag_commit.sh
set -euo pipefail
WT=/Volumes/CrucialX9/flutter_app/build/wt-cui-b376
P=/Volumes/CrucialX9/flutter_app/build/kayan-safe/codex-ui/plan407-ios-profile-diag-314f48ab2/native-profile-diagnostics.patch
cd "$WT"
[ "$(git rev-parse HEAD)" = "$(git rev-parse 6aa735ddb)" ] || { echo "head moved"; exit 3; }
[ "$(shasum -a 256 "$P" | cut -d' ' -f1)" = e2f3498bed6f5bf570a41a8dc99bf3a6cf8e3ae931ecce9cf614068b82c20bf2 ] || { echo "patch sha differs"; exit 3; }
git apply --check "$P"
git apply "$P"
F="ios/NotificationService/NotificationService.swift ios/Runner/AppDelegate.swift ios/Runner/IosNotificationRecoveryCoordinator.swift"
git add -- $F
git diff --cached --name-only | sort | diff - <(printf '%s\n' $F | sort) >/dev/null || { echo "staged set differs"; exit 3; }
git commit -q -m "diag(ios): Codex-UI payload diagnostic (314f48ab2 content, receiver test profile only)" -m "Applied unchanged from Codex-UI patch sha256 e2f3498b; not a product change for main."
git log -1 --format='%H %s'
