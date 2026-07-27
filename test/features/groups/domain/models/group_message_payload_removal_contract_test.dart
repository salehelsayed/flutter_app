import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _retiredModel =
    'lib/features/groups/domain/models/group_message_payload.dart';
const _retiredTest =
    'test/features/groups/domain/models/group_message_payload_test.dart';
const _removalContract =
    'test/features/groups/domain/models/'
    'group_message_payload_removal_contract_test.dart';

void main() {
  final repository = Directory.current.absolute;

  test('DTR10-PAYLOAD-01 removes only the duplicate Dart payload', () {
    expect(
      _file(repository, _retiredModel).existsSync(),
      isFalse,
      reason: 'the duplicate Dart payload model must stay retired',
    );
    expect(
      _file(repository, _retiredTest).existsSync(),
      isFalse,
      reason: 'the duplicate model SUT-only test must stay retired',
    );

    final manifest = _read(repository, 'tool/runtime_roots/runtime_roots.json');
    expect(
      manifest,
      isNot(contains(_retiredModel)),
      reason: 'runtime-root metadata must match the retired source tree',
    );

    final groupGate = _read(repository, 'scripts/run_test_gates.sh');
    expect(
      groupGate,
      contains(_removalContract),
      reason: 'the groups gate must select this removal contract',
    );
    expect(
      groupGate,
      isNot(contains(_retiredTest)),
      reason: 'the groups gate must not select the retired SUT-only test',
    );

    final retiredImport = RegExp(
      r'''(?:^|\n)\s*(?:import|export)\s+['"][^'"]*group_message_payload\.dart['"]''',
      multiLine: true,
    );
    final retiredIdentifier = RegExp(
      r'(?:^|[^A-Za-z0-9_])GroupMessagePayload'
      r'(?:$|[^A-Za-z0-9_])',
      multiLine: true,
    );
    final importHits = <String>[];
    final identifierHits = <String>[];
    for (final file in _libDartFiles(repository)) {
      final relativePath = _relativePath(repository, file);
      if (relativePath == _retiredModel) {
        continue;
      }
      final contents = file.readAsStringSync();
      if (retiredImport.hasMatch(contents)) {
        importHits.add(relativePath);
      }
      if (retiredIdentifier.hasMatch(contents)) {
        identifierHits.add(relativePath);
      }
    }
    expect(
      importHits,
      isEmpty,
      reason: 'no production Dart import/export may target the retired model',
    );
    expect(
      identifierHits,
      isEmpty,
      reason: 'no production Dart declaration or use may retain the old type',
    );

    final fileStructure = _read(repository, 'C4/file-structure.md');
    expect(
      fileStructure,
      isNot(contains('group_message_payload.dart  # Wire format')),
      reason: 'the current Dart file tree must not advertise the retired file',
    );

    final code = _read(repository, 'C4/code.md');
    expect(
      RegExp(
        r'GroupMessagePayload[\s\S]{0,600}'
        r'fromJson\(Map\): Payload[\s\S]{0,160}toJson\(\): Map',
      ).hasMatch(code),
      isFalse,
      reason: 'the current Dart model diagram must not advertise the duplicate',
    );

    final components = _read(repository, 'C4/components.md');
    expect(
      RegExp(
        r'^\| GroupMessagePayload \| Wire Model \|',
        multiLine: true,
      ).hasMatch(components),
      isFalse,
      reason: 'the Flutter model inventory must not advertise the duplicate',
    );
    expect(
      components,
      contains('Group Envelope Module (internal/group_envelope.go)'),
      reason: 'the live Go group-envelope component must remain documented',
    );
    expect(
      components,
      contains(
        'GroupMessagePayload (text, timestamp, username, extra)',
      ),
      reason: 'the live Go inner payload must remain documented',
    );

    final infrastructure = _read(repository, 'C4/infrastructure.md');
    expect(
      infrastructure,
      contains('**v3 (group encrypted + signed):**'),
      reason: 'the live v3 publish/receive flow must remain documented',
    );
    expect(
      infrastructure,
      contains('Encrypt + sign + publish v3 envelope'),
      reason: 'the live v3 publish command must remain documented',
    );

    final groupEnvelope = _read(
      repository,
      'go-mknoon/internal/group_envelope.go',
    );
    expect(groupEnvelope, contains('type GroupEnvelope struct'));
    expect(groupEnvelope, contains('type GroupMessagePayload struct'));
    expect(groupEnvelope, contains('func MarshalGroupPayload('));
    expect(groupEnvelope, contains('func ParseGroupPayload('));

    final pubsub = _read(repository, 'go-mknoon/node/pubsub.go');
    expect(pubsub, contains('payload := &internal.GroupMessagePayload{'));
    expect(pubsub, contains('internal.MarshalGroupPayload(payload)'));
    expect(pubsub, contains('func buildGroupMessageReceivedEvent('));

    final roadmap = _read(
      repository,
      'Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md',
    );
    expect(
      roadmap,
      contains(
        '[282](282-duplicate-dart-group-message-payload-removal-tdd-plan.md) '
        'are implementation-complete',
      ),
      reason: 'the DTR-10 registry must record the implemented leaf',
    );
    expect(
      roadmap,
      contains(
        '| Retire the duplicate Dart group-message payload | DTR-10 Plan 282 '
        '| Groups + crypto + release | Implemented 2026-07-27 |',
      ),
      reason: 'DTR10-AUTH-06 must record the implemented decision',
    );
    expect(
      roadmap,
      contains('| `DTR08-COMP-009` | **Implementation-complete under Plan 282.**'),
      reason: 'the compatibility overlay must record the Dart-only result',
    );
    expect(
      roadmap,
      contains(_removalContract),
      reason: 'DTR08-COMP-009 must name the surviving causal proof',
    );
    expect(
      roadmap,
      isNot(contains('flutter test --no-pub $_retiredTest')),
      reason: 'DTR08-COMP-009 must not invoke the deleted test',
    );

    final index = _read(repository, 'Test-Flight-Improv/00-INDEX.md');
    expect(
      index,
      contains(
        '**Implementation-complete DTR-10 / `DTR10-AUTH-06` '
        '(2026-07-27)**',
      ),
      reason: 'the current plan index must not leave Plan 282 execution-ready',
    );
  });
}

File _file(Directory repository, String relativePath) {
  return File(
    '${repository.path}${Platform.pathSeparator}'
    '${relativePath.replaceAll('/', Platform.pathSeparator)}',
  );
}

String _read(Directory repository, String relativePath) {
  final file = _file(repository, relativePath);
  if (!file.existsSync()) {
    throw StateError('Required repository file is missing: $relativePath');
  }
  return file.readAsStringSync();
}

List<File> _libDartFiles(Directory repository) {
  final lib = Directory(
    '${repository.path}${Platform.pathSeparator}lib',
  );
  if (!lib.existsSync()) {
    throw StateError('Required production Dart root is missing: lib');
  }
  final files = lib
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  return files;
}

String _relativePath(Directory repository, File file) {
  final prefix = '${repository.path}${Platform.pathSeparator}';
  return file.path
      .substring(prefix.length)
      .replaceAll(Platform.pathSeparator, '/');
}
