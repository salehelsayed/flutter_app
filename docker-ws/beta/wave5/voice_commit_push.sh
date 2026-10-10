#!/bin/bash
# User-approved 2026-10-07: commit the voice playback fix (5 files) on
# wave3-baseline-20260930, fast-forward main to it, push both.
set -eu
cd /Volumes/CrucialX9/flutter_app
git add -- lib/features/conversation/presentation/screens/conversation_wired.dart \
  lib/shared/widgets/media/audio_player_widget.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/shared/fakes/fake_just_audio.dart \
  test/shared/widgets/media/audio_player_widget_test.dart
git diff --cached --stat
git commit -q -F - <<'EOF'
fix(voice): play your own voice message right after sending it

After a successful send, the chat painted the attachment the send use case
returned, which carries the stored relative path (media/<peer>/<id>.m4a).
just_audio could not open it (ENOENT on Android), the load error was
swallowed, and the play button did nothing until the chat was reopened.
Reproduced twice on two Android API 37 emulators.

- conversation_wired: resolve the returned voice media for display, like
  every hydrated message.
- audio_player_widget: emit AUDIO_PLAYER_LOAD_FAILED (with pathIsAbsolute)
  instead of failing silently.
- Regression tests, both red before the fix: the sender's bubble gets an
  absolute, existing path; a failed load is logged. The fake just_audio
  platform can now fail a load (enqueueLoadFailure); before, it accepted
  any path, which is why no host test caught this.

58 affected test files pass (1,419 tests). On the emulators, two fresh
voice messages played on the first tap after sending.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
git log --oneline -1
git fetch . wave3-baseline-20260930:refs/heads/main
git push origin wave3-baseline-20260930 main 2>&1 | tail -3
git ls-remote origin refs/heads/main refs/heads/wave3-baseline-20260930
