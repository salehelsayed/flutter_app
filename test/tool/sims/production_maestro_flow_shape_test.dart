import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('reopen flow waits past a slow phone cold start before asserting '
      'Orbit', () {
    // A debug build on an Android 8.1 Honor JSN-L22 reached runApp 16.7 s
    // after launch; Maestro's default assertVisible wait gave up at ~17 s.
    final flow =
        loadYamlDocuments(
              File(
                'integration_test/maestro/production_reopen_seeded.yaml',
              ).readAsStringSync(),
            ).last.contents
            as YamlList;
    final steps = flow.toList();
    final launch = steps.indexOf('launchApp');
    expect(launch, greaterThanOrEqualTo(0));
    final wait = (steps[launch + 1] as YamlMap)['extendedWaitUntil'] as YamlMap;
    expect(wait['visible'], {'id': 'orbit.view.all_chats'});
    expect(wait['timeout'], greaterThanOrEqualTo(45000));
  });

  test('group send returns to Orbit with bounded backs, not hideKeyboard', () {
    // On an Android 8.1 Honor (SwiftKey) hideKeyboard after a send left the
    // chat, so the following back exited the app to the launcher.
    final flow =
        loadYamlDocuments(
              File(
                'integration_test/maestro/production_group_send.yaml',
              ).readAsStringSync(),
            ).last.contents
            as YamlList;
    expect(flow, isNot(contains('hideKeyboard')));
    expect(flow, isNot(contains('back')));
    final repeat =
        flow.whereType<YamlMap>().singleWhere(
              (s) => s['repeat'] != null,
            )['repeat']
            as YamlMap;
    expect(flow.whereType<YamlMap>().last['assertVisible'], {
      'id': 'orbit.view.inner_circle',
    });
    expect(repeat['while'], {
      'notVisible': {'id': 'orbit.view.inner_circle'},
    });
    expect(repeat['times'], 2);
    expect(repeat['commands'], ['back']);
  });

  test('group create flows tap the name field by id, not by its hint', () {
    // Android 8.1 exposes a Flutter text field's hint as neither text nor
    // hint, so a hint-text selector never matched on the Honor JSN-L22.
    for (final name in [
      'production_group_create',
      'production_catalog_group_create',
      'production_catalog_group_create_verbatim',
    ]) {
      final source = File(
        'integration_test/maestro/$name.yaml',
      ).readAsStringSync();
      expect(source, isNot(contains('Group name')), reason: name);
      final flow = loadYamlDocuments(source).last.contents as YamlList;
      expect(
        flow.whereType<YamlMap>().any(
          (step) =>
              step['tapOn'] is YamlMap &&
              (step['tapOn'] as YamlMap)['id'] == 'group_name_field',
        ),
        isTrue,
        reason: name,
      );
    }
  });

  test('home tabs flow presses back again when the first back only '
      'dismissed the composer', () {
    final flow =
        loadYamlDocuments(
              File(
                'integration_test/maestro/production_home_tabs.yaml',
              ).readAsStringSync(),
            ).last.contents
            as YamlList;
    final backs = flow
        .whereType<YamlMap>()
        .where((step) => step['repeat'] != null)
        .map((step) => step['repeat'] as YamlMap)
        .toList();
    expect(backs, hasLength(1));
    final repeat = backs.single;
    expect(repeat['while'], {'notVisible': r'(?s)^Intros.*$'});
    expect(repeat['times'], greaterThanOrEqualTo(2));
    expect(repeat['times'], lessThanOrEqualTo(3));
    expect(flow.whereType<YamlMap>().last['assertVisible'], r'(?s)^Intros.*$');
  });

  test('invite revoke flow scrolls the member row into view before tapping '
      'Revoke on a 360x800 dp screen', () {
    final flow =
        loadYamlDocuments(
              File(
                'integration_test/maestro/production_group_invite_revoke.yaml',
              ).readAsStringSync(),
            ).last.contents
            as YamlList;
    final steps = flow.toList();
    final scroll = steps.indexWhere(
      (step) =>
          step is YamlMap &&
          step['scrollUntilVisible'] is YamlMap &&
          (step['scrollUntilVisible'] as YamlMap)['element'] == 'Revoke',
    );
    expect(scroll, isNonNegative);
    expect(
      steps.indexWhere((step) => step is YamlMap && step['tapOn'] == 'Revoke'),
      greaterThan(scroll),
    );
  });

  test('private open flow brings the whole message tile into view before '
      'tapping it', () {
    final steps =
        (loadYamlDocuments(
                  File(
                    'integration_test/maestro/production_private_open.yaml',
                  ).readAsStringSync(),
                ).last.contents
                as YamlList)
            .toList();
    const tile = r'conversation.private.${MESSAGE_ID}';
    final scroll = steps.indexWhere(
      (step) =>
          step is YamlMap &&
          step['scrollUntilVisible'] is YamlMap &&
          (step['scrollUntilVisible'] as YamlMap)['element'] is YamlMap &&
          ((step['scrollUntilVisible'] as YamlMap)['element']
                  as YamlMap)['id'] ==
              tile,
    );
    expect(scroll, isNonNegative);
    expect(
      (steps[scroll] as YamlMap)['scrollUntilVisible']['centerElement'],
      isTrue,
    );
    final tap = steps.indexWhere(
      (step) =>
          step is YamlMap &&
          step['tapOn'] is YamlMap &&
          (step['tapOn'] as YamlMap)['id'] == tile,
    );
    expect(tap, greaterThan(scroll));
  });
}
