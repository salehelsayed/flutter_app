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

// Plans 347 and 370 deliberately add app-owned lifecycle callbacks ahead of
// incumbent recovery; the DTR-18 relocation and feature-import floor stay
// unchanged.
const _resumeSha256 =
    '59e79cb5247d99e0481c952e0ded0de88dd173f1edb268b9332375037c3a9e30';
const _contactSha256 =
    'd177b34246373d54d3ff3541603c465ae82b89550ea02f1dcdb30f6e30deee5b';
const _privacySha256 =
    '302be89b18d29b3997e171a2859084eb44a8a5360c7e24e6b3d85c3b6883f718';
// Plan 360 adds exactly ONE optional field to MyApp — the linked-device trust
// capability — and threads it to the Orbit and Conversation hosts so the
// contact profile can receive a non-null capability. It relocates nothing and
// keeps ApplicationRoot's incumbent unconditional `deferredRuntimeStartup`
// callback and its signature.
//
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
// Plan 361 adds the route-push fanout authoring resolver seam, the linked
// blob-free modality gate at the SAME ConversationWired construction site,
// and the linked-role resume/pause filters ahead of the incumbent owners.
// Nothing relocates and no core shim returns.
// Plan 362 makes the linked modality gate selector-triple aware, adds the
// optional restricted strict-media resume converger hook, and nothing
// relocates.
// Plan 362 post-audit repair: the three linked-device route values
// (fanout resolver, device trust, modality gate) collapse into ONE
// DirectConversationRouteAuthority getter that is now threaded to StartupRouter
// and the Orbit host, so ordinary navigation reaches the same authority the
// notification route always had. The notification push reads the same getter
// instead of recomputing the gate inline, which is why the three selector flag
// imports and the modality-gate import fall away. Composition only — nothing
// relocates and no core shim returns.
// The final Task-10 composition also forwards the linked-media drain through
// MyApp's existing cold/resume hook; this is the same app-owned runtime seam,
// not a restored core dependency.
// Plan 363 adds only the restricted protected-group recovery callbacks and
// their linked-role lifecycle ordering on that same application root. Plan
// 364 extends the same linked lifecycle owner with protected blob-free content
// retry quiescence and a generation-bound pause lease; nothing relocates.
// Plan 365 adds the two strict group-media progress callbacks and runs the
// existing protected-content owner to a bounded fixed point on linked resume;
// this remains app-owned lifecycle composition and relocates nothing.
// Plan 370 forwards the single default-off completed-outcome drain callback
// through that same application-owned resume boundary; nothing relocates.
const _applicationRootNormalizedSha256 =
    'cf9caa9b0e25f718c2ce99584f321cb3a632d783e082365ad676aac1d9e7f21a';
// Plan 358 forwards the strict local-path commit's `nowMs` sample through the
// same already-wired delegate and relocates nothing. Plan 360 additionally
// constructs the role-aware deferred-runtime-start owner over the SAME
// `startLiveServicesIfAllowed` closure and passes the database-backed
// linked-device trust capability to MyApp; it also publishes that owner's
// resolved transport peer to the already-present P2P service's synchronous
// qualifier through one forward reference. The Plan-360 bounded repair adds
// three more wirings on the same already-present owners: the authority load is
// bound to the current account peer, the logical account peer is published to
// the P2P migration gate, and the shipping receiver start is wrapped by the
// linked-destination precondition. Nothing moved.
// Plan 361 composes the shared reverse transport authority, the v113
// blob-free fanout/purge/settle delegates on the SAME repository
// constructions, the four listener authority wirings, the restricted
// DirectBlobFreeLinkedServices behind the SAME deferred linked callback,
// and the exact linked drain plus route-push resolver seams to MyApp.
// Nothing moved and no core shim returned.
// Plan 362 injects the v114 linked-media fanout snapshot/generation/v108
// delegates and the incoming reverse-recheck transport pass-through on the
// SAME media repository construction; its post-audit repair additionally
// wires the last-reference artifact counter into the SAME drain
// construction. Nothing moved.
// Plan 362 post-audit repair: binds the linked-scoped custody states loader on
// the SAME media repository construction, adds one local converger closure over
// the SAME single drain instance, and supplies it to the restricted linked
// services at cold start and to MyApp on resume — closing a hook the
// application root already declared and awaited but nothing ever filled. It
// also threads the shared route-authority bundle into StartupRouter. All
// composition on already-present owners; nothing moved. Task-10's physical
// linked-sender repair additionally forwards the already-authenticated
// transport peer into the existing media SQL-stage delegate and declares the
// captured P2P service before that drain closure; this changes wiring/order
// only and introduces no adapter or core shim.
// Plan 363 composes protected bootstrap/authority persistence, replay and
// read-only refresh through this same production root; its audit closures add
// sender history, common proof recovery, durable survivor progress, exact
// PREPARED recovery/abort, bounded terminal-free restart discovery, strict
// native metadata completion, and exact row-owned key-draft restart recovery
// without relocating an adapter or core shim.
// The final same-epoch sibling rearm closure keeps that composition in this
// root while exposing the exact persisted-PREPARED survivor matcher for a
// production-path regression; no ownership boundary moved.
// Plan 364 composes the owner-keyed authoring resolver, protected content
// ingress/reconciliation, strict retry quiescence, and the linked narrow
// surface on those same repositories and runtime owners. Its final repair
// defers pending-key replay until protected authority is COMPLETE. No adapter
// moved.
const _productionBootstrapNormalizedSha256 =
    // Plan 365 wires the existing strict group-media lifecycle owner into the
    // local cold-start cleanup sequence; no bootstrap responsibility moves.
    // Plan 366 adds the plural direct-private media generation and Barrier-B
    // delegates plus fresh-share authorization pass-throughs on the same
    // repository constructions; composition remains app-owned.
    // Plan 369 adds validated installation-identity resolution and default-off
    // completed-outcome producer seams at that same app-owned composition
    // boundary; it does not move an adapter or introduce a core shim.
    // Plan 370 composes the one default-off, production-tested drain factory
    // and threads its callback through existing retry/resume owners; no
    // adapter boundary moves.
    '33d16b84d267ac928748dac692d4b49b2932db2aba195b7491e3376e2b77ea2a';

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
