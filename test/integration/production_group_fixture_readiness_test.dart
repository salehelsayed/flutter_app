import 'dart:async';
import 'dart:io';

import 'package:flutter_app/debug/production_journeys/production_group_fixture_controls.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fixture group creation waits for in-flight group recovery', () async {
    final gate = GroupRecoveryGate();
    final release = Completer<void>();
    final pass = gate.run(() => release.future);

    var idle = false;
    final wait = awaitProductionFixtureGroupRecoveryIdle(
      gate: gate,
    ).then((_) => idle = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(idle, isFalse);

    release.complete();
    await pass;
    await wait;
    expect(idle, isTrue);
    expect(gate.isActive, isFalse);
  });

  test('fixture recovery wait is bounded', () async {
    final gate = GroupRecoveryGate()..begin();
    await expectLater(
      awaitProductionFixtureGroupRecoveryIdle(
        gate: gate,
        timeout: const Duration(milliseconds: 30),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('fixture rejects a group whose member was not added', () {
    final group = GroupModel(
      id: 'g1',
      name: 'fixture',
      type: GroupType.chat,
      topicName: 'topic',
      myRole: GroupRole.admin,
      createdAt: DateTime.utc(2026),
      createdBy: 'alice',
    );
    expect(
      () => requireProductionFixtureMembersAdded(
        CreateGroupWithMembersResult(
          group: group,
          membersAdded: 0,
          addMemberFailures: const [
            CreateGroupMemberAddFailure(peerId: 'bob', username: 'Bob'),
          ],
        ),
      ),
      throwsStateError,
    );
    requireProductionFixtureMembersAdded(
      CreateGroupWithMembersResult(group: group, membersAdded: 1),
    );
  });

  test('prepare_group waits for recovery and requires every member', () {
    final source = File(
      'lib/debug/production_journeys/production_group_fixture_controls.dart',
    ).readAsStringSync();
    final prepare = source.substring(
      source.indexOf("bindAction('prepare_group'"),
      source.indexOf("bindAction('import_group'"),
    );
    final wait = prepare.indexOf('awaitProductionFixtureGroupRecoveryIdle(');
    final create = prepare.indexOf('createGroupWithMembers(');
    expect(wait, greaterThanOrEqualTo(0));
    expect(wait, lessThan(create));
    expect(prepare, contains('requireProductionFixtureMembersAdded(result)'));
  });
}
