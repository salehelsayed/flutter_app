import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/update_check_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const _policy = UpdatePlatformPolicy(
  latestBuild: 120,
  minBuild: 100,
  reasonCode: UpdateReasonCode.security,
);

UpdateDecision _decide(String installed, {int? dismissed}) => decideUpdate(
  installedBuildNumber: installed,
  policy: _policy,
  dismissedLatestBuild: dismissed,
);

void main() {
  group('decision (AC1)', () {
    test('below minBuild -> hard', () {
      expect(
        _decide('99'),
        const UpdateDecisionHard(
          minBuild: 100,
          reasonCode: UpdateReasonCode.security,
        ),
      );
    });

    test('between minBuild and latestBuild -> soft', () {
      expect(
        _decide('100'),
        const UpdateDecisionSoft(
          latestBuild: 120,
          reasonCode: UpdateReasonCode.security,
        ),
      );
    });

    test('installed == latestBuild -> none', () {
      expect(_decide('120'), const UpdateDecisionNone());
    });

    test('above latestBuild -> none', () {
      expect(_decide('121'), const UpdateDecisionNone());
    });

    test('build number that cannot be parsed -> none', () {
      for (final raw in ['', 'abc', '1.0.0', '12a']) {
        expect(_decide(raw), const UpdateDecisionNone(), reason: raw);
      }
      // Surrounding whitespace is tolerated.
      expect(_decide(' 99 '), isA<UpdateDecisionHard>());
    });

    test('no policy -> none', () {
      expect(
        decideUpdate(
          installedBuildNumber: '1',
          policy: null,
          dismissedLatestBuild: null,
        ),
        const UpdateDecisionNone(),
      );
    });

    test('dismissal holds for the same latestBuild only', () {
      expect(_decide('110', dismissed: 120), const UpdateDecisionNone());
      expect(_decide('110', dismissed: 119), isA<UpdateDecisionSoft>());
    });

    test('dismissal never hides a hard decision', () {
      expect(_decide('99', dismissed: 120), isA<UpdateDecisionHard>());
    });
  });

  group('schedule (AC8)', () {
    final last = DateTime.utc(2026, 10, 10, 12);

    test('due at launch', () {
      expect(
        isUpdateCheckDue(
          now: last.add(const Duration(minutes: 1)),
          lastCheckAt: last,
          checkedThisLaunch: false,
        ),
        isTrue,
      );
    });

    test('due when never checked', () {
      expect(
        isUpdateCheckDue(now: last, lastCheckAt: null, checkedThisLaunch: true),
        isTrue,
      );
    });

    test('not due within 6 h', () {
      for (final elapsed in [
        Duration.zero,
        const Duration(hours: 5, minutes: 59),
        const Duration(hours: 6),
      ]) {
        expect(
          isUpdateCheckDue(
            now: last.add(elapsed),
            lastCheckAt: last,
            checkedThisLaunch: true,
          ),
          isFalse,
          reason: '$elapsed',
        );
      }
    });

    test('due after more than 6 h', () {
      expect(
        isUpdateCheckDue(
          now: last.add(const Duration(hours: 6, seconds: 1)),
          lastCheckAt: last,
          checkedThisLaunch: true,
        ),
        isTrue,
      );
    });

    test('due when the clock went back', () {
      expect(
        isUpdateCheckDue(
          now: last.subtract(const Duration(seconds: 1)),
          lastCheckAt: last,
          checkedThisLaunch: true,
        ),
        isTrue,
      );
    });
  });

  test('reason codes parse; unknown or missing -> general (O3)', () {
    expect(UpdateReasonCode.parse('general'), UpdateReasonCode.general);
    expect(UpdateReasonCode.parse('security'), UpdateReasonCode.security);
    expect(
      UpdateReasonCode.parse('protocol_change'),
      UpdateReasonCode.protocolChange,
    );
    expect(
      UpdateReasonCode.parse('critical_fix'),
      UpdateReasonCode.criticalFix,
    );
    expect(UpdateReasonCode.parse('SECURITY'), UpdateReasonCode.general);
    expect(UpdateReasonCode.parse(null), UpdateReasonCode.general);
  });
}
