#!/bin/bash
# Analyze + format-check the voice fix files, then rebuild the APK (voice_build_apk.sh inline).
set -u
cd /Volumes/CrucialX9/flutter_app || exit 1
SDK=$HOME/development/flutter-3.47.2/bin
FILES="lib/features/conversation/presentation/screens/conversation_wired.dart lib/shared/widgets/media/audio_player_widget.dart test/shared/fakes/fake_just_audio.dart test/shared/widgets/media/audio_player_widget_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart"
echo "=== analyze"; "$SDK/flutter" analyze --no-pub $FILES 2>&1 | tail -4
echo "=== format check"; "$SDK/dart" format --output=none --set-exit-if-changed $FILES 2>&1 | tail -4; echo "format exit=$?"
