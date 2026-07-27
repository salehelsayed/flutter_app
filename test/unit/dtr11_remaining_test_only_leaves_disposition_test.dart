import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _originalTestOnlyAppPaths = <String>{
  'lib/features/contact_request/presentation/widgets/'
      'pending_requests_badge.dart',
  'lib/features/conversation/presentation/widgets/reaction_display.dart',
  'lib/features/feed/application/feed_projection.dart',
  'lib/features/identity/application/'
      'recover_identity_from_secure_store_use_case.dart',
  'lib/features/introduction/presentation/widgets/intros_tab.dart',
  'lib/features/p2p/application/discover_peer_use_case.dart',
  'lib/features/p2p/application/send_message_use_case.dart',
  'lib/features/p2p/application/stop_node_use_case.dart',
  'lib/features/push/application/push_preview_telemetry_gate.dart',
  'lib/features/qr_code/application/handle_scanned_qr_use_case.dart',
  'lib/features/qr_code/domain/models/qr_payload_model.dart',
};

const _retiredSutOnlyTests = <String>{
  'test/features/contact_request/presentation/widgets/'
      'pending_requests_badge_test.dart',
  'test/features/conversation/presentation/widgets/reaction_display_test.dart',
  'test/features/identity/application/'
      'recover_identity_from_secure_store_use_case_test.dart',
  'test/features/introduction/presentation/widgets/intros_tab_test.dart',
  'test/features/introduction/presentation/widgets/intros_tab_extended_test.dart',
  'test/features/p2p/application/discover_peer_use_case_test.dart',
  'test/features/p2p/application/send_message_use_case_test.dart',
  'test/features/p2p/application/stop_node_use_case_test.dart',
  'test/features/qr_code/application/handle_scanned_qr_use_case_test.dart',
  'test/features/qr_code/domain/models/qr_payload_model_test.dart',
};

void main() {
  final repository = Directory.current.absolute;

  test(
    'DTR-11 maps every remaining test-only leaf and preserves live owners',
    () {
      final violations = <String>[];
      final manifest = _read(
        repository,
        'tool/runtime_roots/runtime_roots.json',
      );

      for (final path in _originalTestOnlyAppPaths) {
        if (_file(repository, path).existsSync()) {
          violations.add('original-app-path:$path');
        }
        if (manifest.contains('"path": "$path"')) {
          violations.add('manifest-declaration:$path');
        }
      }
      for (final path in _retiredSutOnlyTests) {
        if (_file(repository, path).existsSync()) {
          violations.add('sut-only-test:$path');
        }
      }

      const toolingTelemetryPath =
          'tool/telemetry/push_preview_telemetry_gate.dart';
      final toolingTelemetry = _file(repository, toolingTelemetryPath);
      if (!toolingTelemetry.existsSync()) {
        violations.add('tooling-telemetry:$toolingTelemetryPath');
      } else {
        final source = toolingTelemetry.readAsStringSync();
        for (final anchor in <String>[
          'pushPreviewDegradeRateBlockThreshold = 0.03',
          'calculatePushPreviewDegradeRate(',
          'bool get blocksRelease',
        ]) {
          if (!source.contains(anchor)) {
            violations.add('tooling-telemetry-anchor:$anchor');
          }
        }
      }

      const migratedProofAnchors = <String, List<String>>{
        'test/features/feed/application/feed_projection_test.dart': <String>[
          'features/feed/application/feed_store.dart',
          'replaceContactSnapshot(',
          'replaceGroupSnapshot(',
        ],
        'test/features/push/application/'
            'push_preview_telemetry_gate_test.dart': <String>[
          'tool/telemetry/push_preview_telemetry_gate.dart',
        ],
        'test/features/orbit/presentation/screens/'
            'orbit_screen_archived_groups_test.dart': <String>[
          'folded live intro preserves peer-id attribution fallback and long '
              'names stay actionable',
        ],
        'test/features/qr_code/presentation/screens/'
            'qr_scanner_wired_test.dart': <String>[
          'contact QR sends an encrypted request and isolates profile '
              'download failure',
        ],
      };
      for (final entry in migratedProofAnchors.entries) {
        final source = _requiredSource(repository, entry.key, violations);
        for (final anchor in entry.value) {
          if (source != null && !source.contains(anchor)) {
            violations.add('migrated-proof:${entry.key}:$anchor');
          }
        }
      }

      final letterCardTest = _requiredSource(
        repository,
        'test/features/conversation/presentation/widgets/letter_card_test.dart',
        violations,
      );
      if (letterCardTest != null &&
          letterCardTest.contains('ReactionDisplay')) {
        violations.add('stale-reaction-type-assertion:letter_card_test.dart');
      }

      const liveAnchorsByPath = <String, List<String>>{
        'lib/features/contact_request/application/'
            'contact_request_notification_materializer.dart': <String>[
          'class ContactRequestNotificationMaterializer',
        ],
        'lib/features/feed/presentation/screens/feed_wired.dart': <String>[
          'ContactRequestDialog(',
          '_feedStore.replaceContactSnapshot(',
          '_feedStore.replaceGroupSnapshot(',
        ],
        'lib/features/conversation/presentation/widgets/letter_card.dart':
            <String>['_buildReactionChipWidgets('],
        'lib/features/feed/application/feed_store.dart': <String>[
          'void replaceContactSnapshot(',
          'void replaceGroupSnapshot(',
        ],
        'lib/features/identity/application/restore_identity_use_case.dart':
            <String>['restoreIdentityFromMnemonic('],
        'test/features/identity/presentation/screens/'
            'startup_router_recovery_test.dart': <String>[
          'needsIdentity ignores surviving secure-store mnemonic and stays on '
              'onboarding',
        ],
        'lib/features/orbit/presentation/screens/orbit_screen.dart': <String>[
          '_buildIntroSliver(',
          '_buildIntroEntries(',
        ],
        'lib/features/introduction/presentation/widgets/intro_row.dart':
            <String>['class IntroRow extends StatelessWidget'],
        'lib/core/services/p2p_service.dart': <String>[
          'Future<bool> stopNode();',
          'Future<bool> sendMessage(',
          'Future<DiscoveredPeer?> discoverPeer(',
        ],
        'lib/features/qr_code/application/build_qr_payload_use_case.dart':
            <String>['buildQRPayload('],
        'lib/features/qr_code/application/parse_qr_payload_use_case.dart':
            <String>['parseQRPayload('],
        'lib/features/qr_code/presentation/screens/qr_scanner_wired.dart':
            <String>[
              'class QRScannerWired extends StatelessWidget',
              'final (result, contact) = await parseQRPayload(',
            ],
      };
      for (final entry in liveAnchorsByPath.entries) {
        final source = _requiredSource(repository, entry.key, violations);
        for (final anchor in entry.value) {
          if (source != null && !source.contains(anchor)) {
            violations.add('live-anchor:${entry.key}:$anchor');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'DTR11-RED: the exact residual leaves/bookkeeping remain, or their '
            'mapped live owners and migrated proof are incomplete:\n'
            '${violations.join('\n')}',
      );
    },
  );

  test('DTR-11 dispositions all four upstream carry-ins exactly', () {
    final violations = <String>[];

    final sendChat = _read(
      repository,
      'lib/features/conversation/application/'
      'send_chat_message_use_case.dart',
    );
    for (final anchor in <String>[
      'if (failure.relayProbeEligible)',
      'relayProbeEligible: relayProbeEligible',
      "relayProbeEligible: true",
      'relayProbeEligible: sendTimedOut',
    ]) {
      if (!sendChat.contains(anchor)) {
        violations.add('relay-classification-anchor:$anchor');
      }
    }

    final backlog = _read(
      repository,
      'lib/features/groups/presentation/group_backlog_retention_notice.dart',
    );
    if (backlog.contains('listSummary')) {
      violations.add('dead-backlog-field:listSummary');
    }
    for (final anchor in <String>[
      'groupBacklogRetentionNoticeFor(',
      'bannerText:',
      'emptyTitle:',
      'emptySubtitle:',
    ]) {
      if (!backlog.contains(anchor)) {
        violations.add('backlog-live-anchor:$anchor');
      }
    }

    final routingHarness = _read(
      repository,
      'integration_test/routing_smoke_harness.dart',
    );
    final routingRunner = _read(
      repository,
      'integration_test/scripts/run_routing_smoke_e2e.dart',
    );
    for (final token in <String>[
      'CHAT_MSG_SEND_RELAY_PROBE_BEGIN',
      's15ProbeEvents',
      'probeAttempted',
    ]) {
      if (routingHarness.contains(token) || routingRunner.contains(token)) {
        violations.add('inert-routing-diagnostic:$token');
      }
    }
    for (final anchor in <String>[
      "s15Details['sendPath']",
      "s15Details['outcome']",
    ]) {
      if (!routingHarness.contains(anchor)) {
        violations.add('routing-harness-live-anchor:$anchor');
      }
    }
    for (final anchor in <String>[
      "s15Alice['outcome'] == 'success'",
      "s15Alice['sendPath']",
      "s15Bob['e2eMs']",
    ]) {
      if (!routingRunner.contains(anchor)) {
        violations.add('routing-runner-live-anchor:$anchor');
      }
    }

    final coreGate = _read(repository, 'scripts/run_host_test_gates.sh');
    if (!coreGate.contains("rg --files test/unit -g '*_test.dart'")) {
      violations.add('unit-family-registration:core-host-all');
    }
    final gateContract = _read(
      repository,
      'scripts/test/host_test_gate_batch_contract_test.sh',
    );
    for (final anchor in <String>[
      'expected_unit_paths',
      'actual_unit_paths',
      'core-host-all omitted or duplicated test/unit paths',
    ]) {
      if (!gateContract.contains(anchor)) {
        violations.add('unit-family-contract:$anchor');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'DTR11-CARRYIN-RED: an upstream carry-in is missing its exact '
          'terminal disposition:\n${violations.join('\n')}',
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

String? _requiredSource(
  Directory repository,
  String relativePath,
  List<String> violations,
) {
  final file = _file(repository, relativePath);
  if (!file.existsSync()) {
    violations.add('live-file:$relativePath');
    return null;
  }
  return file.readAsStringSync();
}
