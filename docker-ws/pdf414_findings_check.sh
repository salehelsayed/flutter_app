#!/bin/bash
# Plan 414 findings fix: Dart tests, then Android JVM tests.
D="$(cd "$(dirname "$0")" && pwd)"
bash "$D/pdf414_test_names.sh" findings_dart_names.txt \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  test/features/share/presentation/share_target_picker_wired_test.dart \
  test/core/notifications/main_activity_onnewintent_pin_test.dart \
  test/core/media/ test/shared/widgets/media/document_attachment_tile_test.dart
bash "$D/pdf414_kotlin_egress.sh" findings_kotlin.txt
