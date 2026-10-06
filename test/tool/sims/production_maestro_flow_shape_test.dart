import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
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
