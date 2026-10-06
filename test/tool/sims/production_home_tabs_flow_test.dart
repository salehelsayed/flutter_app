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
}
