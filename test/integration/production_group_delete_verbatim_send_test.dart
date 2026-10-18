import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group delete direct sends type through the verbatim keyboard when '
      'installed', () {
    // On a USB Honor JSN-L22 (SwiftKey), production_direct_send's
    // hideKeyboard left the focused composer unable to receive inputText.
    final runner = File(
      'integration_test/scripts/run_production_group_delete_preserves_friends.dart',
    ).readAsStringSync();
    // A per-device session keeps the verbatim keyboard across sends: restoring
    // the device keyboard while the composer has focus opens it, and the next
    // back only closes it (seen on the phone after alice-send-bob).
    expect(runner, contains('ProductionVerbatimKeyboardSession('));
    expect(runner, isNot(contains('withProductionVerbatimKeyboard(')));
    expect(
      runner,
      matches(
        RegExp(
          r'finally \{\s*await restoreKeyboards\(\);\s*await journey\.restore\(\);',
        ),
      ),
    );
    expect(
      runner,
      matches(
        RegExp(
          r"verbatim\s*\?\s*'production_verbatim_send'\s*:\s*'production_direct_send'",
        ),
      ),
    );
    expect(runner, contains("proof['keyboardSwitches']"));
  });
}
