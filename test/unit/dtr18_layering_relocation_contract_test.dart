import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _contractPath = 'test/unit/dtr18_layering_relocation_contract_test.dart';
const _oldResumePath = 'lib/core/lifecycle/handle_app_resumed.dart';
const _newResumePath = 'lib/app/lifecycle/handle_app_resumed.dart';
const _oldResumeUri =
    'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
const _newResumeUri =
    'package:flutter_app/app/lifecycle/handle_app_resumed.dart';

const _oldContactPath =
    'lib/features/posts/domain/repositories/'
    'contact_presence_snapshot_repository_impl.dart';
const _newContactPath =
    'lib/features/posts/data/repositories/'
    'contact_presence_snapshot_repository_impl.dart';
const _oldContactUri =
    'package:flutter_app/features/posts/domain/repositories/'
    'contact_presence_snapshot_repository_impl.dart';
const _newContactUri =
    'package:flutter_app/features/posts/data/repositories/'
    'contact_presence_snapshot_repository_impl.dart';

const _oldPrivacyPath =
    'lib/features/posts/domain/repositories/'
    'posts_privacy_settings_repository_impl.dart';
const _newPrivacyPath =
    'lib/features/posts/data/repositories/'
    'posts_privacy_settings_repository_impl.dart';
const _oldPrivacyUri =
    'package:flutter_app/features/posts/domain/repositories/'
    'posts_privacy_settings_repository_impl.dart';
const _newPrivacyUri =
    'package:flutter_app/features/posts/data/repositories/'
    'posts_privacy_settings_repository_impl.dart';

const _closureConsumerUriRewrites = <String, String>{
  'package:flutter_app/features/contact_request/data/repositories/'
          'contact_request_repository_impl.dart':
      'package:flutter_app/features/contact_request/domain/repositories/'
      'contact_request_repository_impl.dart',
  'package:flutter_app/features/contacts/data/repositories/'
          'contact_repository_impl.dart':
      'package:flutter_app/features/contacts/domain/repositories/'
      'contact_repository_impl.dart',
  'package:flutter_app/features/conversation/data/repositories/'
          'media_attachment_repository_impl.dart':
      'package:flutter_app/features/conversation/domain/repositories/'
      'media_attachment_repository_impl.dart',
  'package:flutter_app/features/conversation/data/repositories/'
          'message_repository_impl.dart':
      'package:flutter_app/features/conversation/domain/repositories/'
      'message_repository_impl.dart',
  'package:flutter_app/features/conversation/data/repositories/'
          'reaction_repository_impl.dart':
      'package:flutter_app/features/conversation/domain/repositories/'
      'reaction_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_exit_diagnostic_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_exit_diagnostic_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_exit_intent_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_exit_intent_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_history_gap_repair_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_history_gap_repair_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_invite_delivery_attempt_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_invite_delivery_attempt_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_message_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_message_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_pending_broadcast_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_pending_broadcast_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_pending_key_distribution_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_pending_key_distribution_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_pending_key_repair_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_pending_key_repair_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_pending_membership_message_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_pending_membership_message_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_pending_reaction_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_pending_reaction_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_reaction_replay_outbox_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_reaction_replay_outbox_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'group_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'group_repository_impl.dart',
  'package:flutter_app/features/groups/data/repositories/'
          'pending_group_invite_repository_impl.dart':
      'package:flutter_app/features/groups/domain/repositories/'
      'pending_group_invite_repository_impl.dart',
  'package:flutter_app/features/identity/data/repositories/'
          'identity_repository_impl.dart':
      'package:flutter_app/features/identity/domain/repositories/'
      'identity_repository_impl.dart',
  'package:flutter_app/features/introduction/data/repositories/'
          'intro_review_seen_repository_impl.dart':
      'package:flutter_app/features/introduction/domain/repositories/'
      'intro_review_seen_repository_impl.dart',
  'package:flutter_app/features/introduction/data/repositories/'
          'introduction_repository_impl.dart':
      'package:flutter_app/features/introduction/domain/repositories/'
      'introduction_repository_impl.dart',
  'package:flutter_app/features/posts/data/repositories/'
          'post_repository_impl.dart':
      'package:flutter_app/features/posts/domain/repositories/'
      'post_repository_impl.dart',
};

// Plan 347 deliberately adds local cleanup plus the exact custody drain ahead
// of mutable upload retry; the DTR-18 relocation and feature-import floor stay
// unchanged.
const _resumeSha256 =
    '019ed707358a864cbee8021f4881bbe6b3e45ec4e39bf8adc2d334261a05814c';
const _contactSha256 =
    'd177b34246373d54d3ff3541603c465ae82b89550ea02f1dcdb30f6e30deee5b';
const _privacySha256 =
    '302be89b18d29b3997e171a2859084eb44a8a5360c7e24e6b3d85c3b6883f718';
// Plans 347/348 wire the reviewed cleanup/drain and absent-parent v111 stage
// through MyApp and production bootstrap; Plan 350 adds only the optional
// forward-authorization pass-through on that same wired stage. Plan 353 adds
// three more closures on that same wired media adapter (caption-edit
// qualification, the atomic caption+v109 stage, and the incoming conditional
// apply) and relocates nothing. Plan 354 adds exactly two more closures on
// that same wired stage — the private v111 generation stage and the private
// envelope+v108+v111 inbox-custody handoff — plus the incoming private stage
// closure and the drain's private no-auto-download retention policy, and
// relocates nothing. Plan 355 additionally makes canonical keep and the
// display projection retire terminal private media and routes the drain
// through one shared predicate, still relocating nothing. Plan 356 adds exactly
// one more closure on that same wired message adapter — the atomic private
// tombstone + physical-v109 stage — and relocates nothing. Posts
// adapter bodies remain byte-identical.
const _applicationRootNormalizedSha256 =
    '6d918b2711d85c92dc8cfaef2ce508805b4642bec4d6fb2bb9e5ddf9a16d5162';
// Plan 358 forwards the strict local-path commit's `nowMs` sample through the
// same already-wired delegate and relocates nothing.
const _productionBootstrapNormalizedSha256 =
    '1d7df44e861fabbcda440328136a66d6e005e53ae80cb0fc40435b525bc0af11';

const _reviewedResumeExceptionTargets = <String>{
  'lib/features/account_migration/application/'
      'account_migration_runtime_network_gate.dart',
  'lib/features/contact_request/application/'
      'retry_incomplete_key_exchanges_use_case.dart',
  'lib/features/contacts/domain/repositories/contact_repository.dart',
  'lib/features/conversation/domain/repositories/'
      'media_attachment_repository.dart',
  'lib/features/conversation/domain/repositories/reaction_repository.dart',
  'lib/features/groups/application/drain_group_offline_inbox_use_case.dart',
  'lib/features/groups/application/group_message_listener.dart',
  'lib/features/groups/application/group_pending_key_repair_service.dart',
  'lib/features/groups/application/group_recovery_gate.dart',
  'lib/features/groups/application/'
      'reconcile_missed_group_dissolves_use_case.dart',
  'lib/features/groups/application/rejoin_group_topics_use_case.dart',
  'lib/features/groups/domain/repositories/'
      'group_history_gap_repair_repository.dart',
  'lib/features/groups/domain/repositories/group_message_repository.dart',
  'lib/features/groups/domain/repositories/'
      'group_pending_key_repair_repository.dart',
  'lib/features/groups/domain/repositories/'
      'group_pending_reaction_repository.dart',
  'lib/features/groups/domain/repositories/group_repository.dart',
  'lib/features/identity/domain/repositories/identity_repository.dart',
  'lib/features/posts/application/nearby_location_service.dart',
};

const _resumeDirectiveFiles = <String>{
  'integration_test/benchmark_background_resume_harness.dart',
  'integration_test/routing_smoke_harness.dart',
  'integration_test/soak_e2e_test.dart',
  'integration_test/transport_e2e_test.dart',
  'lib/app/application_root.dart',
  'lib/app/bootstrap/production_application_bootstrap.dart',
  'test/core/lifecycle/app_lifecycle_recovery_test.dart',
  'test/core/lifecycle/background_reconnect_smoke_test.dart',
  'test/core/lifecycle/connectivity_lifecycle_test.dart',
  'test/core/lifecycle/handle_app_resumed_export_pause_recovery_test.dart',
  'test/core/lifecycle/handle_app_resumed_group_download_recovery_test.dart',
  'test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart',
  'test/core/lifecycle/handle_app_resumed_group_media_cleanup_test.dart',
  'test/core/lifecycle/handle_app_resumed_group_recovery_test.dart',
  'test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart',
  'test/core/lifecycle/handle_app_resumed_key_distribution_test.dart',
  'test/core/lifecycle/handle_app_resumed_parallel_reprime_test.dart',
  'test/core/lifecycle/handle_app_resumed_pending_key_repair_sweep_test.dart',
  'test/core/lifecycle/handle_app_resumed_stuck_sending_test.dart',
  'test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart',
  'test/core/lifecycle/handle_app_resumed_warm_peer_test.dart',
  'test/core/lifecycle/pause_resume_retry_smoke_test.dart',
  'test/core/lifecycle/private_media_lifecycle_recovery_wiring_test.dart',
  'test/core/resilience/network_failover_test.dart',
  'test/core/services/p2p_service_fault_injection_test.dart',
  'test/features/contact_request/application/'
      'key_exchange_retry_smoke_test.dart',
  'test/features/groups/integration/group_resume_recovery_test.dart',
  'test/features/groups/integration/group_startup_rejoin_smoke_test.dart',
  'test/features/identity/presentation/screens/'
      'startup_router_recovery_test.dart',
  'test/features/introduction/application/'
      'introduction_outbound_delivery_test.dart',
  'test/features/posts/phase3/handle_app_resumed_nearby_test.dart',
  'test/shared/fakes/test_user.dart',
  'test/shared/helpers/lifecycle_helpers.dart',
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

String _fileSha256(Directory root, String path) =>
    sha256.convert(File('${root.path}/$path').readAsBytesSync()).toString();

Iterable<File> _dartFiles(Directory root) sync* {
  for (final topLevel in const <String>['lib', 'test', 'integration_test']) {
    final directory = Directory('${root.path}/$topLevel');
    if (!directory.existsSync()) {
      continue;
    }
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final relative = entity.path
            .substring(root.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        if (relative != _contractPath) {
          yield entity;
        }
      }
    }
  }
}

Set<String> _directiveFiles(Directory root, String uri) {
  final directive = "import '$uri';";
  return <String>{
    for (final file in _dartFiles(root))
      if (file.readAsLinesSync().map((line) => line.trim()).contains(directive))
        file.path
            .substring(root.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/'),
  };
}

Set<String> _featureImportTargets(String source) {
  return RegExp(
    r"^import 'package:flutter_app/(features/[^']+\.dart)';$",
    multiLine: true,
  ).allMatches(source).map((match) => 'lib/${match.group(1)!}').toSet();
}

String _normalizedConsumerSha256(Directory root, String path) {
  var normalized = _source(root, path)
      .replaceAll(_newResumeUri, _oldResumeUri)
      .replaceAll(_newContactUri, _oldContactUri)
      .replaceAll(_newPrivacyUri, _oldPrivacyUri);
  for (final rewrite in _closureConsumerUriRewrites.entries) {
    normalized = normalized.replaceAll(rewrite.key, rewrite.value);
  }
  return sha256.convert(utf8.encode(normalized)).toString();
}

void main() {
  final root = _repositoryRoot();

  test('DTR-18 relocates resume orchestration to app without a core shim', () {
    expect(File('${root.path}/$_newResumePath').existsSync(), isTrue);
    expect(File('${root.path}/$_oldResumePath').existsSync(), isFalse);
    expect(_fileSha256(root, _newResumePath), _resumeSha256);
    expect(
      _featureImportTargets(_source(root, _newResumePath)),
      _reviewedResumeExceptionTargets,
      reason: 'the moved source must retain the 18 reviewed feature imports',
    );

    expect(_directiveFiles(root, _newResumeUri), _resumeDirectiveFiles);
    expect(_directiveFiles(root, _oldResumeUri), isEmpty);

    for (final path in const <String>[
      'test/core/lifecycle/'
          'handle_app_resumed_phase2_continuation_wiring_test.dart',
      'test/core/lifecycle/'
          'handle_app_resumed_pending_key_repair_sweep_test.dart',
    ]) {
      final source = _source(root, path);
      expect(source, contains("'$_newResumePath'"), reason: path);
      expect(source, isNot(contains("'$_oldResumePath'")), reason: path);
    }

    final applicationRoot = _source(root, 'lib/app/application_root.dart');
    expect(
      RegExp(
        r'if\s*\(\s*state\s*==\s*AppLifecycleState\.resumed\s*\)'
        r'\s*\{\s*_onResumed\(\);\s*\}',
        multiLine: true,
      ).hasMatch(applicationRoot),
      isTrue,
      reason:
          'ApplicationRoot must keep foreground-resume dispatch to '
          '_onResumed',
    );
    expect(
      _normalizedConsumerSha256(root, 'lib/app/application_root.dart'),
      _applicationRootNormalizedSha256,
    );
    expect(
      _normalizedConsumerSha256(
        root,
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ),
      _productionBootstrapNormalizedSha256,
    );
  });

  test('DTR-18 relocates the two Posts Phase-3 adapters to data', () {
    for (final oldPath in const <String>[_oldContactPath, _oldPrivacyPath]) {
      expect(File('${root.path}/$oldPath').existsSync(), isFalse);
    }
    expect(_fileSha256(root, _newContactPath), _contactSha256);
    expect(_fileSha256(root, _newPrivacyPath), _privacySha256);

    expect(_directiveFiles(root, _oldContactUri), isEmpty);
    expect(_directiveFiles(root, _oldPrivacyUri), isEmpty);
    expect(_directiveFiles(root, _newContactUri), <String>{
      'lib/app/application_root.dart',
      'lib/app/bootstrap/production_application_bootstrap.dart',
      'test/features/posts/phase3/contact_presence_snapshot_repository_test.dart',
    });
    expect(_directiveFiles(root, _newPrivacyUri), <String>{
      'lib/app/application_root.dart',
      'lib/app/bootstrap/production_application_bootstrap.dart',
      'test/features/posts/phase3/posts_privacy_settings_repository_test.dart',
    });

    expect(
      _normalizedConsumerSha256(root, 'lib/app/application_root.dart'),
      _applicationRootNormalizedSha256,
    );
    expect(
      _normalizedConsumerSha256(
        root,
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ),
      _productionBootstrapNormalizedSha256,
    );
  });

  test('DTR-18 removes only the reviewed exception identities', () {
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
    final placements = (manifest['placementExceptions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(dependencies, hasLength(165));
    expect(placements, isEmpty);
    expect(_reviewedResumeExceptionTargets, hasLength(18));
    for (final target in _reviewedResumeExceptionTargets) {
      expect(
        dependencies.where(
          (entry) =>
              entry['rule'] == 'core-must-not-depend-on-feature' &&
              entry['source'] == _oldResumePath &&
              entry['directiveKind'] == 'import' &&
              entry['target'] == target,
        ),
        isEmpty,
        reason: 'reviewed DTR-18 dependency identity must be removed: $target',
      );
    }
    expect(
      dependencies.where(
        (entry) =>
            entry['source'] == _oldResumePath ||
            entry['source'] == _newResumePath,
      ),
      isEmpty,
    );
    expect(
      placements.where(
        (entry) => <String>{
          _oldContactPath,
          _newContactPath,
          _oldPrivacyPath,
          _newPrivacyPath,
        }.contains(entry['path']),
      ),
      isEmpty,
    );
    expect(
      dependencies.where(
        (entry) => entry['source'] == 'lib/core/services/p2p_service_impl.dart',
      ),
      hasLength(8),
    );
    expect(
      dependencies.where(
        (entry) =>
            entry['source'] == 'lib/core/lifecycle/handle_app_paused.dart',
      ),
      hasLength(8),
    );

    final dtr16Contract = _source(
      root,
      'test/features/groups/application/'
      'group_message_listener_decomposition_contract_test.dart',
    );
    expect(
      RegExp(
        r'expect\(\s*facadeExceptions,\s*isEmpty,',
        multiLine: true,
      ).hasMatch(dtr16Contract),
      isTrue,
      reason: 'the removed resume-to-listener exception must not be retargeted',
    );
    expect(dtr16Contract, contains("'DTR-16',"));
    expect(
      dtr16Contract,
      contains('isNot(contains(forbidden))'),
      reason: 'the DTR-16 no-exception safeguard must remain',
    );
  });
}
