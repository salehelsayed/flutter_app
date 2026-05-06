---
name: onNewIntent fix working-tree status
description: The MainActivity.kt onNewIntent fix for flutter_local_notifications on singleTask is in the working tree (uncommitted) at SHA 5fec83b3
type: project
---

The `onNewIntent` override in `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt` that calls `super.onNewIntent(intent)` then `setIntent(intent)` is present in the working tree as of 2026-05-05 but NOT committed.

**Why:** The fix was diagnosed during a hardware soak on 2026-05-05 (Pixel 6 / Android 16). It closes finding `notif-tap-2026-05-05-001`. The hardware soak that discovered the bug (commit 5fec83b3 "Snapshot WIP: 2026-05-05 hardware soak — Android notification tap callback never fires") was made before the fix was written.

**How to apply:** When checking notification-tap-to-route status, verify whether this fix has been committed. `git show HEAD:android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt` should show an `onNewIntent` override. If not, finding 001 is still open at committed HEAD even if the working tree looks fixed.
