import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/android_production_audio_call_campaign.dart';

/// kx0007 (VUI-7 device-audio restart2): the caller's shade opened, then the
/// app took focus again (a new activity intent) and the loop kept dumping the
/// app UI until its 45 s deadline, because it expanded the shade only once.
/// Each loop pass must reopen the shade when the dump is not SystemUI.
const _systemUi = 'com.android.systemui';
const _title = 'Plan399Callee';

String _row(String inner, {String bounds = '[0,100][1080,400]'}) =>
    '<node package="$_systemUi" '
    'resource-id="$_systemUi:id/expandableNotificationRow" '
    'bounds="$bounds">$inner</node>';

String _text(String text, {String bounds = '[40,120][600,160]'}) =>
    '<node package="$_systemUi" text="$text" bounds="$bounds"/>';

String _hierarchy(String inner) =>
    '<?xml version="1.0" encoding="UTF-8"?><hierarchy rotation="0">$inner</hierarchy>';

void main() {
  const allowed = {_systemUi};

  test('an app-owned dump reopens the notification shade', () {
    final xml = _hierarchy(
      '<node package="com.mknoon.sims.productionaudio" '
      'resource-id="com.mknoon.sims.productionaudio:id/call_root" '
      'bounds="[0,0][1080,2400]"><node package="com.mknoon.sims.productionaudio" '
      'text="Connected" bounds="[40,200][600,260]"/></node>',
    );

    final step = androidCallBackNotificationStep(
      xml,
      title: _title,
      allowedPackages: allowed,
    );

    expect(step.kind, AndroidCallBackNotificationStepKind.reopenShade);
    expect(step.center, isNull);
  });

  test('a collapsed matching row taps its Expand button', () {
    final xml = _hierarchy(
      _row(
        '${_text(_title)}${_text('Missed call', bounds: '[40,170][600,210]')}'
        '<node package="$_systemUi" resource-id="$_systemUi:id/expand_button" '
        'content-desc="Expand" bounds="[960,120][1040,200]"/>',
      ),
    );

    final step = androidCallBackNotificationStep(
      xml,
      title: _title,
      allowedPackages: allowed,
    );

    expect(step.kind, AndroidCallBackNotificationStepKind.expand);
    expect(step.center, (1000, 160));
  });

  test('an expanded matching row taps its Call back action', () {
    final xml = _hierarchy(
      _row(
        '${_text(_title)}${_text('Missed call', bounds: '[40,170][600,210]')}'
        '<node package="$_systemUi" text="Call back" clickable="true" '
        'enabled="true" bounds="[100,300][400,380]"/>',
      ),
    );

    final step = androidCallBackNotificationStep(
      xml,
      title: _title,
      allowedPackages: allowed,
    );

    expect(step.kind, AndroidCallBackNotificationStepKind.tapAction);
    expect(step.center, (250, 340));
  });

  test('an open shade without the row waits instead of reopening', () {
    final xml = _hierarchy(
      _row('${_text('Other app')}${_text('Something else')}'),
    );

    final step = androidCallBackNotificationStep(
      xml,
      title: _title,
      allowedPackages: allowed,
    );

    expect(step.kind, AndroidCallBackNotificationStepKind.wait);
  });
}
