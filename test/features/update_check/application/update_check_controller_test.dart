import 'dart:async';

import 'package:flutter_app/features/update_check/application/update_check_controller.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_update_check_service.dart';

const _hard = UpdateDecisionHard(
  minBuild: 120,
  reasonCode: UpdateReasonCode.security,
);
const _soft120 = UpdateDecisionSoft(
  latestBuild: 120,
  reasonCode: UpdateReasonCode.general,
);
const _soft121 = UpdateDecisionSoft(
  latestBuild: 121,
  reasonCode: UpdateReasonCode.general,
);
const _none = UpdateDecisionNone();

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('nothing runs before start, and start runs one check', () async {
    final service = FakeUpdateCheckService(decisions: [_hard]);
    final controller = UpdateCheckController(service: service);
    addTearDown(controller.dispose);

    await controller.onResumed();
    expect(service.checks, 0);
    expect(controller.value, _none);

    controller.start();
    controller.start();
    await _settle();
    expect(service.checks, 1);
    expect(controller.value, _hard);
    expect(controller.installedBuildNumber, '118');
    expect(controller.platform, UpdatePlatform.ios);
  });

  test('hard rechecks on every resume, even when no check is due', () async {
    final service = FakeUpdateCheckService(decisions: [_hard, _hard, _none]);
    final controller = UpdateCheckController(service: service);
    addTearDown(controller.dispose);
    controller.start();
    await _settle();

    await controller.onResumed();
    expect(service.checks, 2);
    expect(service.dueQueries, 0);
    expect(controller.value, _hard);

    await controller.onResumed();
    expect(service.checks, 3);
    expect(controller.value, _none);
  });

  test('without hard, resume checks only when a check is due', () async {
    final service = FakeUpdateCheckService(decisions: [_none, _soft120]);
    final controller = UpdateCheckController(service: service);
    addTearDown(controller.dispose);
    controller.start();
    await _settle();

    await controller.onResumed();
    expect(service.dueQueries, 1);
    expect(service.checks, 1);

    service.due = true;
    await controller.onResumed();
    expect(service.checks, 2);
    expect(controller.value, _soft120);
  });

  test('a dismissal holds for that latestBuild and a higher one shows '
      'again', () async {
    final service = FakeUpdateCheckService(
      decisions: [_soft120, _soft120, _soft121],
      due: true,
    );
    final controller = UpdateCheckController(service: service);
    addTearDown(controller.dispose);
    controller.start();
    await _settle();
    expect(controller.value, _soft120);

    await controller.dismissSoft();
    expect(controller.value, _none);
    expect(service.dismissed, [120]);

    // Even a service that still reports 120 cannot bring it back.
    await controller.onResumed();
    expect(controller.value, _none);

    await controller.onResumed();
    expect(controller.value, _soft121);
  });

  test('a check that was running during the dismissal does not undo '
      'it', () async {
    final service = FakeUpdateCheckService(
      decisions: [_soft120, _soft120],
      due: true,
    );
    final controller = UpdateCheckController(service: service);
    addTearDown(controller.dispose);
    controller.start();
    await _settle();

    final gate = service.gate = Completer<void>();
    final resume = controller.onResumed();
    await _settle();
    await controller.dismissSoft();
    gate.complete();
    await resume;
    expect(controller.value, _none);
  });

  test('dismissSoft does nothing without a soft decision', () async {
    final service = FakeUpdateCheckService(decisions: [_hard]);
    final controller = UpdateCheckController(service: service);
    addTearDown(controller.dispose);
    controller.start();
    await _settle();

    await controller.dismissSoft();
    expect(service.dismissed, isEmpty);
    expect(controller.value, _hard);
  });

  test('a result that arrives after dispose is dropped', () async {
    final service = FakeUpdateCheckService(decisions: [_hard]);
    final gate = service.gate = Completer<void>();
    final controller = UpdateCheckController(service: service);
    controller.start();
    controller.dispose();
    gate.complete();
    await _settle();
    expect(service.checks, 1);
  });
}
