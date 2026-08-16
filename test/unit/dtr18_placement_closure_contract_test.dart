import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _contractPath = 'test/unit/dtr18_placement_closure_contract_test.dart';
const _dependencyIdentitySha256 =
    '50c21d843f8ee7833b000b203a8ab4397f3330f05b05c32452d0769939acd338';
const _dependencyDispositionSha256 =
    '0a4729898bd543a28c128aa6ee4a72f52a88e7c4bdf6644e5aee7ec21e0991c3';
const _residualEvidence =
    'DTR18-AUTH-02 terminal residual disposition dated 2026-07-28.';

// Plan 374 shipped the debug-only device seed/inspection fixture with four
// reviewed core->feature imports; Plan 375 adopted it for the fixed-wake
// proof. These rows are receipt-bound, not DTR18-AUTH-02 residuals.
const _plan374FixtureEvidence =
    'Plan-374 checksum receipt (Test-Flight-Improv/evidence/374/README.md) '
    'binds the fixture and its TC-374-08 device proof; adopted unchanged by '
    'the Plan-375 fixed-wake proof.';

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
    // Plan 361 adds the serialized contact-conversation purge capability
    // delegate (dbPurgeDirectContactConversationAndContact) and its
    // reconciliation surface to the SAME data adapter; nothing relocates.
    'ef67291da37df1e3edb35b95c7b1419fb78762c709a0bdff47bae5f19d31cd96',
  ],
  'lib/features/conversation/domain/repositories/'
      'media_attachment_repository_impl.dart': <String>[
    'lib/features/conversation/data/repositories/'
        'media_attachment_repository_impl.dart',
    // Plans 347/348 add exact v111 generation, terminalization, incoming
    // custody ownership, and the reviewed fresh absent-parent stage to the
    // already-relocated Conversation adapter. Plan 350 generalizes that stage
    // to exactly two canonical parent shapes and Plan 351 adds the deletion
    // lane selector plus the atomic strict-media deletion stage — all without
    // relocating anything. Plan 353 adds the caption-edit qualification, the
    // atomic caption stage and the incoming conditional apply to the same
    // adapter. Plan 354 adds the private v111 generation stage over the exact
    // convention-pending projection — still no relocation. Plan 358 threads the
    // strict owner's own sampled clock through the incoming local-path commit
    // so a disappearing deadline is requalified inside that transaction; the
    // adapter still owns exactly the same responsibilities in the same place.
    // Plan 362 makes the v111 authority direction/target-explicit (natural
    // (attachment, direction, recipient) lookups), adds the linked-media
    // fanout generation + per-target v108 batch stages and the in-transaction
    // reverse-transport recheck seam on the incoming stages; nothing
    // relocates.
    // The Plan-362 execution's final format pass reflowed this adapter after
    // the first repin; the digest below is the formatted body.
    // Plan 362 post-audit repair: the adapter additionally implements the
    // restricted linked drain scope (one capability getter plus one
    // linked-scoped states loader) so the linked runtime converges only rows
    // it owns. The Task-10 real-device repair further threads the authenticated
    // physical sender into this same adapter's plural v108 stage so SQL can
    // validate linked outer envelopes without rewriting the logical parent.
    // Both are capabilities on the same adapter — nothing relocates.
    // The Plan-362 Task-10 body landed with this formatted digest; the prior
    // lock still carried its pre-final-format value even though the adapter
    // itself is unchanged by Plan 363.
    // Plan 365 adds lane-qualified group custody staging/load/CAS/cleanup and
    // its read-only crash-orphan path inventory to this same relocated media
    // adapter; nothing moves.
    // Plan 366 adds the plural direct-private generation stage and the exact
    // fresh-share/authorized-forward inputs to that adapter; placement and
    // dependency direction stay unchanged.
    'cf565a40d732b59394efedfcb9ce40a1a841ae3ba2f5f28df808fbe5534bb992',
  ],
  'lib/features/conversation/domain/repositories/'
      'message_repository_impl.dart': <String>[
    'lib/features/conversation/data/repositories/message_repository_impl.dart',
    // Plans 347 and 349 publish the strict incoming parent/attachment and
    // ordinary-text mutation projections; Plan 351 adds the transactional
    // incoming-deletion owner and the typed strict publication disposition.
    // Plan 354 adds the private envelope+v108+v111 inbox-custody handoff, and
    // Plan 355 makes strict incoming publication suppress every exact private
    // terminal state rather than only deleted/hidden. Plan 356 adds exactly one
    // optional delegate plus its capability getter and staging method for the
    // atomic private tombstone + physical-v109 transaction. The adapter remains
    // in data.
    // Plan 361 threads the fanout-generation receipt settlement expectation
    // through the already-wired upload settle delegate; the adapter remains
    // in data with nothing relocated.
    // Plan 366 adds the plural private Barrier-B delegate and its exact
    // current-snapshot/persisted-survivor validation to this same data
    // adapter; no repository responsibility changes layer.
    '79c4335ba5182596d8cdc9399b646fa4a3474cd322db7de51664adaa0ca27642',
  ],
  'lib/features/conversation/domain/repositories/'
      'reaction_repository_impl.dart': <String>[
    'lib/features/conversation/data/repositories/reaction_repository_impl.dart',
    // Plan 361 adds the v113 reaction fanout stage and the linked
    // in-transaction reaction apply delegates to the SAME data adapter;
    // nothing relocates.
    'bfab8703792dc98c332f12b7f27bf03f6baf9f4431028a2549b43930bbd37ed7',
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
    // Plan 364 adds the narrow protected-content prepared-owner/CAS
    // capabilities to this already-relocated adapter; placement is unchanged.
    '501a42e834c6ef2cb6af583819bbbddf6d2ea60bed43288f50f31a4c87e5eaf9',
  ],
  'lib/features/groups/domain/repositories/'
      'group_pending_broadcast_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_pending_broadcast_repository_impl.dart',
    // Plan 363 couples protected persistence with authenticated PREPARED facts,
    // exact recipient retirement and durable exact ABORTED classification in
    // this relocated adapter; placement/stale-import checks remain unchanged.
    '42cd12a9c4ebbd0070e7c57f857e7b1291be0962d332e1d66e39cca08bba749f',
  ],
  'lib/features/groups/domain/repositories/'
      'group_pending_key_distribution_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/'
        'group_pending_key_distribution_repository_impl.dart',
    // Same-epoch sibling rearm makes the existing DB reopen delegate required
    // so every production reopen durably advances its exact-CAS generation;
    // repository placement and stale-source checks remain unchanged.
    '4bc7a0a27d1094b05b926abfc7187606fc2464a86ad0f50d4a37cd23f563cc22',
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
    // Plan 364 extends this existing data adapter with exact protected-content
    // prepared-owner, survivor-CAS, and terminal-completion capabilities.
    'b4d961f80b8529cf7cd68a8d500eeae5d30037ffa7ed1bba5386453cf53b0a6c',
  ],
  'lib/features/groups/domain/repositories/'
      'group_repository_impl.dart': <String>[
    'lib/features/groups/data/repositories/group_repository_impl.dart',
    // Plan 363 adds sender/receiver genesis, atomic key/dissolve completion,
    // metadata PREPARED projection, and exact restart repair to this already-
    // relocated adapter; its placement and stale-import checks remain
    // unchanged.
    '1128da7e6d890736b5ad8b5f14d68440cda277d9d8c6ac4fd0a2c33eee3eca89',
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
    '4b3e115b1941a402ffcf154ab678d1be668f56ab467dc41620b30b08697e7671',
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
    expect(dependencies, hasLength(169));
    expect(
      _dependencyIdentitySha256For(dependencies),
      _dependencyIdentitySha256,
    );
    expect(
      _dependencyDispositionSha256For(dependencies),
      _dependencyDispositionSha256,
    );
    expect(
      dependencies.where(
        (entry) => entry['evidence'] == _plan374FixtureEvidence,
      ),
      hasLength(4),
    );
    expect(
      dependencies.where(
        (entry) =>
            entry['evidence'] != _residualEvidence &&
            entry['evidence'] != _plan374FixtureEvidence,
      ),
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
