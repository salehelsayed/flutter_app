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
}
