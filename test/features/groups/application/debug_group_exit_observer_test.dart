import 'package:flutter_app/features/groups/application/debug_group_exit_observer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugGroupExitObserver = null);

  test('no exit observer is installed by default', () {
    expect(debugGroupExitObserver, isNull);
  });

  test('a debug journey can install and clear an exit observer', () {
    final steps = <String>[];
    debugGroupExitObserver = (step, groupId, details) => steps.add(step);
    notifyGroupExitDebugObserver('notice_prepare', 'g', const {});
    expect(steps, ['notice_prepare']);
    debugGroupExitObserver = null;
    notifyGroupExitDebugObserver('notice_attempt', 'g', const {});
    expect(steps, ['notice_prepare']);
  });

  test('an observer that throws never affects the exit', () {
    debugGroupExitObserver = (step, groupId, details) => throw StateError('x');
    expect(
      () => notifyGroupExitDebugObserver('request_leave', 'g', const {}),
      returnsNormally,
    );
  });
}
