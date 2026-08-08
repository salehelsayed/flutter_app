import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _contractPath = 'test/unit/dtr18_placement_closure_contract_test.dart';
const _dependencyIdentitySha256 =
    'd4f42f151ae18feaf922ad90f172401917a3b7b4ca104d4574e6f9c12a6afb40';
const _dependencyDispositionSha256 =
    '5f24faf4c5f693d0f19eb18503e5d37c4db4580c6ccbc91806abc75a78dcf132';
const _residualEvidence =
    'DTR18-AUTH-02 terminal residual disposition dated 2026-07-28.';

const _relocations = <String, List<String>>{
  'lib/features/contact_request/domain/repositories/'
      'contact_request_repository_impl.dart': <String>[
    'lib/features/contact_request/data/repositories/'
        'contact_request_repository_impl.dart',
    '3471670dde3c51e2c8dec5fd6cd84d412d716b99e64f031d3a0f5b48cfb8ab18',
  ],
  'lib/features/contacts/domain/repositories/'
      'contact_repository_impl.dart': <String>[
    'lib/features/contacts/data/repositories/contact_repository_impl.dart',
    'b632e4f770f8beeb2e4801a0b469dcc7952a12a19496d479376a297a716eb1e2',
  ],
  'lib/features/conversation/domain/repositories/'
      'media_attachment_repository_impl.dart': <String>[
    'lib/features/conversation/data/repositories/'
        'media_attachment_repository_impl.dart',
    // Plan 347 adds exact v111 generation, terminalization, and incoming
    // custody ownership to the already-relocated Conversation adapter.
    '5f2d1a8f5fb9b4643f3d6f082c85de47464eaaf2c09a23c2e21f8f315a5c511a',
  ],
  'lib/features/conversation/domain/repositories/'
      'message_repository_impl.dart': <String>[
    'lib/features/conversation/data/repositories/message_repository_impl.dart',
    // Plan 347 publishes only the already-durable strict incoming parent and
    // attachment projection; the adapter remains in the reviewed data layer.
    '9a9648bdbe9522cc49a5b07a5a4045f11f7a532577d2ae0a54692485e6e10781',
  ],
  'lib/features/conversation/domain/repositories/'
      'reaction_repository_impl.dart': <String>[
    'lib/features/conversation/data/repositories/reaction_repository_impl.dart',
    '095dd392c4c1c8a47efad20985ed1ca04f61ce4932bd903c2de56cef67114278',
  ],
  'lib/features/groups/domain/repositories/'
      'group_exit_diagnostic_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_exit_diagnostic_repository_impl.dart',
    '50640490daad1ed8aa3e45ab2248d89e5f9f224883c4d6540e8cf7e0ef6607e7',
  ],
  'lib/features/groups/domain/repositories/'
      'group_exit_intent_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_exit_intent_repository_impl.dart',
    'fb0f6344390d71bc3206144c9c9a008e8374c2b86f0ec60497db6dfc1694b988',
  ],
  'lib/features/groups/domain/repositories/'
      'group_history_gap_repair_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_history_gap_repair_repository_impl.dart',
    '5991b2a9cad4ff1e5ea4d1695e0623ea8c8cc63c4bc65c9fc9bf4f72bea1e893',
  ],
  'lib/features/groups/domain/repositories/'
      'group_invite_delivery_attempt_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_invite_delivery_attempt_repository_impl.dart',
    '42850e9af2a99bd1617c1f943c448c11db4bd83252a113203863d55f3a7fc27c',
  ],
  'lib/features/groups/domain/repositories/'
      'group_message_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/group_message_repository_impl.dart',
    '370bc07e12068d0491f868b88e63493d8aa0eafe604a704b2c8e668b15de7ed0',
  ],
  'lib/features/groups/domain/repositories/'
      'group_pending_broadcast_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_pending_broadcast_repository_impl.dart',
    '2a61d288bd4719986886a96a54521329f5311bbb5db7f58fb2c0f167d1c12783',
  ],
  'lib/features/groups/domain/repositories/'
      'group_pending_key_distribution_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_pending_key_distribution_repository_impl.dart',
    '040432e247dd6dd2ea631e9b159554e487c5c344b3aef7fe852793cb0c1a578a',
  ],
  'lib/features/groups/domain/repositories/'
      'group_pending_key_repair_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_pending_key_repair_repository_impl.dart',
    '9e11d726d2984dade495d2fde435371ea30b62f3b2d99b25565fa8c6db8d38e1',
  ],
  'lib/features/groups/domain/repositories/'
      'group_pending_membership_message_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_pending_membership_message_repository_impl.dart',
    '35b0cc141b05c185a47130de53dac188a35239c4ff48c55692a7394e70432f38',
  ],
  'lib/features/groups/domain/repositories/'
      'group_pending_reaction_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_pending_reaction_repository_impl.dart',
    '35cd4ccd56b45cdb6d556df7a300b42008d9587e9c803480b6b0214e4b40c537',
  ],
  'lib/features/groups/domain/repositories/'
      'group_reaction_replay_outbox_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_reaction_replay_outbox_repository_impl.dart',
    'c323a1410410d7e238ad8e4f451211910d8b745b54a4a81c0a13245050b0e2bc',
  ],
  'lib/features/groups/domain/repositories/'
      'group_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/group_repository_impl.dart',
    'd25715a537c6160530f32cf5549b8f89b0c171953cc5b129489e54ba0bed3704',
  ],
  'lib/features/groups/domain/repositories/'
      'pending_group_invite_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'pending_group_invite_repository_impl.dart',
    '04eb0b4d54864c308f92689289c24f29587ce2312fdb559f0e4ef9a8ff45fa04',
  ],
  'lib/features/identity/domain/repositories/'
      'identity_repository_impl.dart': <String>[
    'lib/features/identity/data/repositories/identity_repository_impl.dart',
    'b8133f8db2ce827328b96e50dbc5da5e4cd10656b1eb19e30e9fa6356e65fa0c',
  ],
  'lib/features/introduction/domain/repositories/'
      'intro_review_seen_repository_impl.dart': <String>[
    'lib/features/introduction/data/repositories/'
        'intro_review_seen_repository_impl.dart',
    '9eb7924630e89ddfa9603c07669026b9a4f7b010c44d0dc3c457b2f9d6681969',
  ],
  'lib/features/introduction/domain/repositories/'
      'introduction_repository_impl.dart': <String>[
    'lib/features/introduction/data/repositories/'
        'introduction_repository_impl.dart',
    '0b7bdb817d0c3cfcf1b5ba796a603adbb709dabaca7063344706362bea226b53',
  ],
  'lib/features/posts/domain/repositories/'
      'post_repository_impl.dart': <String>[
    'lib/features/posts/data/repositories/post_repository_impl.dart',
    'b24eb65551ed124e9c16455c344ed9e8ec3d568074fe7398581241426faee292',
  ],
};

Directory _repositoryRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (File('${candidate.path}/pubspec.yaml').existsSync() &&
        Directory('${candidate.path}/lib').existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError(
        'Could not locate repository root from ${Directory.current}',
      );
    }
    candidate = parent;
  }
}

String _source(Directory root, String path) =>
    File('${root.path}/$path').readAsStringSync();

String _bodySha256(Directory root, String path) {
  final normalized = _source(root, path)
      .split('\n')
      .where(
        (line) => !line.startsWith('import ') && !line.startsWith('export '),
      )
      .join('\n');
  return sha256.convert(utf8.encode(normalized)).toString();
}

String _dependencyIdentitySha256For(List<Map<String, dynamic>> dependencies) {
  final identities =
      dependencies
          .map(
            (entry) => jsonEncode(<String, dynamic>{
              'rule': entry['rule'],
              'source': entry['source'],
              'directiveKind': entry['directiveKind'],
              'target': entry['target'],
            }),
          )
          .toList()
        ..sort();
  return sha256.convert(utf8.encode('${identities.join('\n')}\n')).toString();
}

String _dependencyDispositionSha256For(
  List<Map<String, dynamic>> dependencies,
) {
  final dispositions =
      dependencies
          .map(
            (entry) => jsonEncode(<String, dynamic>{
              'rule': entry['rule'],
              'source': entry['source'],
              'directiveKind': entry['directiveKind'],
              'target': entry['target'],
              'owner': entry['owner'],
              'reason': entry['reason'],
              'condition': entry['condition'],
              'evidence': entry['evidence'],
            }),
          )
          .toList()
        ..sort();
  return sha256.convert(utf8.encode('${dispositions.join('\n')}\n')).toString();
}

Iterable<File> _dartFiles(Directory root) sync* {
  for (final topLevel in const <String>[
    'lib',
    'test',
    'integration_test',
    'tool',
    'scripts',
  ]) {
    final directory = Directory('${root.path}/$topLevel');
    if (!directory.existsSync()) {
      continue;
    }
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relative = entity.path
          .substring(root.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      if (relative != _contractPath) {
        yield entity;
      }
    }
  }
}

Iterable<File> _sourceLockFiles(Directory root) sync* {
  const extensions = <String>{'.dart', '.sh', '.py', '.js', '.json'};
  for (final topLevel in const <String>[
    'lib',
    'test',
    'integration_test',
    'tool',
    'scripts',
  ]) {
    final directory = Directory('${root.path}/$topLevel');
    if (!directory.existsSync()) {
      continue;
    }
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File ||
          !extensions.any(entity.path.toLowerCase().endsWith)) {
        continue;
      }
      final relative = entity.path
          .substring(root.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      if (relative != _contractPath) {
        yield entity;
      }
    }
  }
}

void _expectRelocatedFamily(
  Directory root,
  bool Function(String oldPath) belongsToFamily,
) {
  for (final entry in _relocations.entries.where(
    (entry) => belongsToFamily(entry.key),
  )) {
    final oldPath = entry.key;
    final destination = entry.value[0];
    final expectedBodySha = entry.value[1];
    expect(
      File('${root.path}/$oldPath').existsSync(),
      isFalse,
      reason: oldPath,
    );
    expect(
      File('${root.path}/$destination').existsSync(),
      isTrue,
      reason: destination,
    );
    expect(
      _bodySha256(root, destination),
      expectedBodySha,
      reason: destination,
    );

    final oldUri = 'package:flutter_app/${oldPath.substring(4)}';
    final staleConsumers = <String>[
      for (final file in _dartFiles(root))
        if (file.readAsStringSync().contains(oldUri))
          file.path
              .substring(root.path.length + 1)
              .replaceAll(Platform.pathSeparator, '/'),
    ];
    expect(staleConsumers, isEmpty, reason: 'stale consumers of $oldUri');

    final staleSourceLocks = <String>[
      for (final file in _sourceLockFiles(root))
        if (file.readAsStringSync().contains(oldPath) ||
            file.readAsStringSync().contains(oldUri))
          file.path
              .substring(root.path.length + 1)
              .replaceAll(Platform.pathSeparator, '/'),
    ];
    expect(
      staleSourceLocks,
      isEmpty,
      reason: 'stale source locks for $oldPath',
    );
  }
}

void main() {
  final root = _repositoryRoot();

  test('DTR-18 relocates all 13 Groups adapters without behavior drift', () {
    _expectRelocatedFamily(
      root,
      (path) => path.startsWith('lib/features/groups/'),
    );
  });

  test('DTR-18 relocates all three Conversation adapters', () {
    _expectRelocatedFamily(
      root,
      (path) => path.startsWith('lib/features/conversation/'),
    );
  });

  test('DTR-18 relocates the six remaining feature adapters', () {
    _expectRelocatedFamily(
      root,
      (path) =>
          !path.startsWith('lib/features/groups/') &&
          !path.startsWith('lib/features/conversation/'),
    );
  });

  test('DTR-18 closes placement debt and retains an exact dependency floor', () {
    final manifest =
        jsonDecode(
              _source(
                root,
                'tool/architecture_guard/architecture_boundary_exceptions.json',
              ),
            )
            as Map<String, dynamic>;
    final dependencies = (manifest['dependencyExceptions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final placements = manifest['placementExceptions'] as List<dynamic>;

    expect(_relocations, hasLength(22));
    expect(placements, isEmpty);
    expect(dependencies, hasLength(165));
    expect(
      _dependencyIdentitySha256For(dependencies),
      _dependencyIdentitySha256,
    );
    expect(
      _dependencyDispositionSha256For(dependencies),
      _dependencyDispositionSha256,
    );
    expect(
      dependencies.where((entry) => entry['evidence'] != _residualEvidence),
      isEmpty,
    );
    expect(
      dependencies.where(
        (entry) =>
            (entry['source'] as String).startsWith('lib/core/debug/') &&
            (entry['condition'] as String).contains('DTR13-AUTH-01'),
      ),
      hasLength(92),
    );
    expect(
      dependencies.where(
        (entry) =>
            entry['source'] == 'lib/core/services/p2p_service_impl.dart' &&
            (entry['condition'] as String).contains('DTR17-AUTH-01'),
      ),
      hasLength(8),
    );
    expect(
      dependencies.where(
        (entry) =>
            entry['source'] == 'lib/core/lifecycle/handle_app_paused.dart' &&
            (entry['condition'] as String).contains('iOS lifecycle'),
      ),
      hasLength(8),
    );
  });
}
