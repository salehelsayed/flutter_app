import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/update_check_notify_policy.dart';
import 'package:flutter_app/features/update_check/domain/update_check_state.dart';
import 'package:flutter_test/flutter_test.dart';

// SE-41 T4a AC2: the pure notify rules with a fake clock.

const _soft = UpdateDecisionSoft(
  latestBuild: 120,
  reasonCode: UpdateReasonCode.general,
);
const _hard = UpdateDecisionHard(
  minBuild: 115,
  reasonCode: UpdateReasonCode.general,
);

UpdateNotifyPlan plan(
  UpdateDecision decision,
  UpdateCheckState state,
  DateTime now, {
  bool foreground = false,
  bool inCall = false,
}) => planUpdateNotification(
  decision: decision,
  state: state,
  now: now,
  foreground: foreground,
  inCall: inCall,
);

void main() {
  final t0 = DateTime.utc(2026, 10, 12, 9);

  test('soft: once per latestBuild', () {
    final first = plan(_soft, UpdateCheckState.empty, t0);
    expect(first, isA<UpdateNotifyPlanPost>());
    final posted = first as UpdateNotifyPlanPost;
    expect(posted.kind, UpdateNotifyKind.soft);
    final state = posted.record(UpdateCheckState.empty);
    expect(state.notifiedSoftLatestBuild, 120);
    expect(
      plan(_soft, state, t0.add(const Duration(days: 30))),
      const UpdateNotifyPlanSkip(UpdateNotifySkip.notDue),
    );
    expect(
      plan(
        const UpdateDecisionSoft(
          latestBuild: 121,
          reasonCode: UpdateReasonCode.general,
        ),
        state,
        t0,
      ),
      isA<UpdateNotifyPlanPost>(),
    );
  });

  test('hard: once, daily x7, then weekly', () {
    var state = UpdateCheckState.empty;
    final posted = <int>[];
    for (var hour = 0; hour <= 24 * 40; hour++) {
      final now = t0.add(Duration(hours: hour));
      final result = plan(_hard, state, now);
      if (result is UpdateNotifyPlanPost) {
        expect(result.kind, UpdateNotifyKind.hard);
        state = result.record(state);
        posted.add(hour ~/ 24);
      }
    }
    expect(posted, [0, 1, 2, 3, 4, 5, 6, 7, 14, 21, 28, 35]);
    expect(state.hardReminderCount, 12);
  });

  test('F1: a lowered minBuild stays in the episode and keeps the schedule', () {
    // 12 reminders already sent for minBuild 118; the publisher lowers it.
    var state = UpdateCheckState(
      notifiedHardMinBuild: 118,
      hardReminderCount: 12,
      lastHardNotifyAt: t0,
    );
    const lowered = UpdateDecisionHard(
      minBuild: 115,
      reasonCode: UpdateReasonCode.general,
    );
    final posted = <int>[];
    for (var hour = 1; hour <= 24 * 30; hour++) {
      final now = t0.add(Duration(hours: hour));
      final result = plan(lowered, state, now);
      if (result is UpdateNotifyPlanPost) {
        // The store keeps the higher tuple; the record must win against it.
        state = UpdateCheckState.merge(state, result.record(state));
        posted.add(hour ~/ 24);
      }
    }
    expect(posted, [7, 14, 21, 28], reason: 'weekly, not every run');
    expect(state.notifiedHardMinBuild, 118);
    // A higher minBuild still starts over at once.
    expect(
      plan(
        const UpdateDecisionHard(
          minBuild: 120,
          reasonCode: UpdateReasonCode.general,
        ),
        state,
        t0.add(const Duration(days: 28, hours: 1)),
      ),
      isA<UpdateNotifyPlanPost>(),
    );
  });

  test('hard: a clock that went back is due', () {
    final state = UpdateCheckState(
      notifiedHardMinBuild: 115,
      hardReminderCount: 3,
      lastHardNotifyAt: t0,
    );
    expect(
      plan(_hard, state, t0.add(const Duration(hours: 1))),
      const UpdateNotifyPlanSkip(UpdateNotifySkip.notDue),
    );
    expect(
      plan(_hard, state, t0.subtract(const Duration(minutes: 1))),
      isA<UpdateNotifyPlanPost>(),
    );
  });

  test('security has its own copy; other codes use the general copy', () {
    for (final code in UpdateReasonCode.values) {
      final result =
          plan(
                UpdateDecisionHard(minBuild: 115, reasonCode: code),
                UpdateCheckState.empty,
                t0,
              )
              as UpdateNotifyPlanPost;
      expect(
        result.copy,
        code == UpdateReasonCode.security
            ? UpdateNotifyCopy.security
            : UpdateNotifyCopy.general,
      );
    }
  });

  test('current build, foreground and call are never notified', () {
    expect(
      plan(const UpdateDecisionNone(), UpdateCheckState.empty, t0),
      const UpdateNotifyPlanSkip(UpdateNotifySkip.noUpdate),
    );
    expect(
      plan(_hard, UpdateCheckState.empty, t0, foreground: true),
      const UpdateNotifyPlanSkip(UpdateNotifySkip.foreground),
    );
    expect(
      plan(_soft, UpdateCheckState.empty, t0, inCall: true),
      const UpdateNotifyPlanSkip(UpdateNotifySkip.inCall),
    );
  });
}
