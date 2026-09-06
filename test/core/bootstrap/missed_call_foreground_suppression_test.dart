import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/notifications/app_visibility_authority.dart';

/// 413: a missed-call card must not arrive while the user is in the app.
///
/// Device 2026-09-06 00:15:42Z: MISSED_CALL_NOTIFICATION_POSTED fired NINE
/// SECONDS after CONV_FL_SCREEN_INIT. The user was in the app, had just
/// watched the call ring and end on the full-screen call overlay, and still
/// got a card — which reads exactly like the "notifications arrive after I
/// open the app" bug.
///
/// The cause was scoping suppression to `maySuppress`, which is true only for
/// the ONE conversation that is visible. The call surface covers the whole
/// app, so foreground at all means the user already saw it.
bool suppressesMissedCallCard(AppVisibilityEvaluation visibility) =>
    visibility.isForegroundActive || visibility.maySuppress;

void main() {
  test('TC-413-01 the app being foreground at all suppresses the card', () {
    // Foreground, but on a DIFFERENT conversation: maySuppress is false.
    const elsewhereInApp = AppVisibilityEvaluation(
      isForegroundActive: true,
      maySuppress: false,
    );

    expect(
      suppressesMissedCallCard(elsewhereInApp),
      isTrue,
      reason:
          'the call overlay covers the whole app, so the user watched this '
          'call end regardless of which screen was underneath',
    );
  });

  test('TC-413-02 the same visible conversation still suppresses', () {
    const sameConversation = AppVisibilityEvaluation(
      isForegroundActive: true,
      maySuppress: true,
    );

    expect(suppressesMissedCallCard(sameConversation), isTrue);
  });

  test('TC-413-03 a backgrounded app still gets the card', () {
    const backgrounded = AppVisibilityEvaluation(
      isForegroundActive: false,
      maySuppress: false,
    );

    expect(
      suppressesMissedCallCard(backgrounded),
      isFalse,
      reason: 'this is the case the whole feature exists for',
    );
  });

  test('TC-413-04 an unreadable snapshot still gets the card', () {
    expect(
      suppressesMissedCallCard(AppVisibilityEvaluation.failNotify),
      isFalse,
      reason: 'failNotify means notify; a missed call must not be lost to a '
          'bad visibility read',
    );
  });
}
