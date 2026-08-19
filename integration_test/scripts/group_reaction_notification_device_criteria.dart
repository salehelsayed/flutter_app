import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../support/android_notification_payload_campaign.dart'
    show relayJournalContainsAndroidProviderSend;
import 'reaction_notification_proof_support.dart';

const String groupReactionNotificationArtifactSchema =
    'mknoon.plan257.device-proof.v1';
const int groupReactionNotificationArtifactVersion = 1;
const String groupReactionNotificationVerdictSchema =
    'mknoon.plan257.orchestrator-verdict.v1';
const String groupReactionNotificationStagingSchema =
    'mknoon.plan257.staging-prerequisites.v1';
const String groupReactionBackgroundConnectedScenarioId =
    'android_group_reaction_recipient_background_connected';
const int groupReactionBackgroundConnectedHomeToReactDelayMs = 3000;
const int groupReactionBackgroundConnectedObservationWindowMs = 60000;
const String groupReactionBackgroundConnectedObservationPrefix =
    'MKNOON_315_BACKGROUND_CONNECTED_OBSERVATION ';
const Set<String> _processAliveReactionScenarioIds = <String>{
  groupReactionBackgroundConnectedScenarioId,
};

bool groupReactionNotificationKeepsRecipientProcessAlive(String scenarioId) =>
    _processAliveReactionScenarioIds.contains(scenarioId);

/// Canonical Android text-target reaction copy after Plan 330.
///
/// The emoji remains part of the authenticated reaction transition, but the
/// notification preview deliberately exposes only the trusted actor and the
/// locally derived semantic target kind.
String groupReactionNotificationExpectedAndroidReactionBody(String actorName) =>
    '$actorName reacted to your message';

/// Builds a least-disclosure probe for the rollout flag inherited by the
/// running relay process. `systemctl show --property=Environment` omits values
/// loaded through EnvironmentFile, which is how the deployed relay is wired.
List<String> groupReactionRelayProcessFlagProbe(String mainPid) {
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(mainPid)) {
    throw const FormatException('relay MainPID must be a positive integer');
  }
  return <String>[
    'sudo',
    'grep',
    '-z',
    '-x',
    '-E',
    r'GROUP_REACTION_PUSH_ENABLED=(1|true)',
    '/proc/$mainPid/environ',
  ];
}

class GroupReactionNotificationStagingValidation {
  GroupReactionNotificationStagingValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;

  String get detail => ok ? 'accepted' : failures.join('; ');
}

/// Validates the declared, redacted staging configuration.
///
/// This is deliberately not a proof of relay/provider readiness. The capture
/// driver independently checks the live relay process, binary digest, rollout
/// flag, provider credentials/config, target inventory, and the eventual
/// provider delivery record before it can emit a passing artifact.
GroupReactionNotificationStagingValidation
validateGroupReactionNotificationStagingManifest(
  Map<String, Object?> value, {
  required GroupReactionNotificationScenario scenario,
}) {
  final failures = <String>[];
  _expectExactKeys(
    value,
    <String>{
      'schema',
      'version',
      'environment',
      'relayActive',
      'providerConfigured',
      'providerProbeSucceeded',
      'productionDeploymentPerformed',
      'allowAppDataReset',
      'candidateRelayRevision',
      'candidateRelaySha256',
      'provider',
      'relayAddresses',
      if (scenario.recipientPlatform == 'ios') 'iosCapture',
    },
    r'$',
    failures,
  );
  _expectValue(
    value,
    'schema',
    groupReactionNotificationStagingSchema,
    r'$',
    failures,
  );
  _expectValue(value, 'version', 1, r'$', failures);
  _expectValue(value, 'environment', 'staging', r'$', failures);
  _expectValue(value, 'relayActive', true, r'$', failures);
  _expectValue(value, 'providerConfigured', true, r'$', failures);
  _expectValue(value, 'providerProbeSucceeded', true, r'$', failures);
  _expectValue(value, 'productionDeploymentPerformed', false, r'$', failures);
  _expectValue(value, 'allowAppDataReset', true, r'$', failures);
  _expectValue(
    value,
    'provider',
    scenario.recipientPlatform == 'ios' ? 'apns' : 'fcm',
    r'$',
    failures,
  );
  for (final key in const <String>[
    'candidateRelayRevision',
    'candidateRelaySha256',
  ]) {
    _requiredString(value, key, r'$', failures);
  }
  final digest = value['candidateRelaySha256'];
  if (digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    failures.add(r'$.candidateRelaySha256 must be a lowercase SHA-256 digest');
  }
  final relayAddresses = value['relayAddresses'];
  if (relayAddresses is! List || relayAddresses.isEmpty) {
    failures.add(r'$.relayAddresses must be a non-empty list');
  } else {
    for (var index = 0; index < relayAddresses.length; index++) {
      final address = relayAddresses[index];
      if (address is! String ||
          address.trim().isEmpty ||
          address.contains(RegExp(r'[\r\n]'))) {
        failures.add(r'$.relayAddresses must contain safe non-empty strings');
        break;
      }
    }
  }
  if (scenario.recipientPlatform == 'ios') {
    final iosCapture = _mapField(value, 'iosCapture', r'$', failures);
    if (iosCapture != null) {
      _expectExactKeys(
        iosCapture,
        const <String>{
          'bundleId',
          'workspace',
          'scheme',
          'fixtureCreateSelector',
          'fixtureAuthorSelector',
          'notificationPrepareSelector',
          'notificationTapSelector',
          'systemLogExecutable',
        },
        r'$.iosCapture',
        failures,
      );
      _expectValue(
        iosCapture,
        'bundleId',
        'com.mknoon.app',
        r'$.iosCapture',
        failures,
      );
      _expectValue(
        iosCapture,
        'workspace',
        'ios/Runner.xcworkspace',
        r'$.iosCapture',
        failures,
      );
      _expectValue(iosCapture, 'scheme', 'Runner', r'$.iosCapture', failures);
      const requiredSelectors = <String, String>{
        'fixtureCreateSelector':
            'RunnerUITests/NotificationTapUITests/'
            'testCreateAnnouncementReactionFixture',
        'fixtureAuthorSelector':
            'RunnerUITests/NotificationTapUITests/'
            'testAuthorAnnouncementReactionTarget',
        'notificationPrepareSelector':
            'RunnerUITests/NotificationTapUITests/'
            'testPrepareWarmNotificationTap',
        'notificationTapSelector':
            'RunnerUITests/NotificationTapUITests/'
            'testAnnouncementReactionNotificationTap',
      };
      for (final entry in requiredSelectors.entries) {
        _expectValue(
          iosCapture,
          entry.key,
          entry.value,
          r'$.iosCapture',
          failures,
        );
      }
      _expectValue(
        iosCapture,
        'systemLogExecutable',
        'idevicesyslog',
        r'$.iosCapture',
        failures,
      );
    }
  }
  return GroupReactionNotificationStagingValidation(failures);
}

class GroupReactionNotificationEvidenceRequirement {
  const GroupReactionNotificationEvidenceRequirement({
    required this.kind,
    required this.markers,
  });

  final String kind;
  final List<String> markers;
}

class GroupReactionNotificationScenario {
  const GroupReactionNotificationScenario({
    required this.id,
    required this.testCase,
    required this.summary,
    required this.groupType,
    required this.senderRole,
    required this.senderPlatform,
    required this.senderDeviceKind,
    required this.recipientRole,
    required this.recipientPlatform,
    required this.recipientDeviceKind,
    required this.evidenceRequirements,
  });

  final String id;
  final String testCase;
  final String summary;
  final String groupType;
  final String senderRole;
  final String senderPlatform;
  final String senderDeviceKind;
  final String recipientRole;
  final String recipientPlatform;
  final String recipientDeviceKind;
  final List<GroupReactionNotificationEvidenceRequirement> evidenceRequirements;
}

const List<GroupReactionNotificationScenario>
groupReactionNotificationScenarios = <GroupReactionNotificationScenario>[
  GroupReactionNotificationScenario(
    id: 'android_group_message_unread_lifecycle',
    testCase: 'TC-13',
    summary:
        'discussion message dismissal, replacement, notification route, and '
        'Orbit unread lifecycle',
    groupType: 'chat',
    senderRole: 'message_sender',
    senderPlatform: 'android',
    senderDeviceKind: 'emulator',
    recipientRole: 'message_recipient',
    recipientPlatform: 'android',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_message',
          'group_type=chat',
          'relay_store_matched=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_fcm',
        markers: <String>['event=group_message', 'delivery_matched=true'],
      ),
      // Plan 386 / TC-386-02. The relay's own counters, scraped raw before the
      // graded transitions and again after quiescence. This is the only
      // provider evidence relay v1.8.0 can still attribute to this lane.
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay_metrics',
        markers: <String>[
          'MKNOON_386_RELAY_METRICS_PHASE baseline',
          'MKNOON_386_RELAY_METRICS_PHASE final',
          'relay_group_reaction_wake_total',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>['role=message_sender', 'two_messages_committed=true'],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'route_target_matched=true',
          'conversation_read_committed=true',
          'both_messages_visible=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>['unread=0,1,1,2,0', 'read_commit_before_tap=false'],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_notification_records',
        markers: <String>[
          'dismissal_observed=true',
          'replacement_observed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'ui_automation',
        markers: <String>[
          'orbit=0,1,1,2,0',
          'orbit_indicators_after_return=0',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: 'android_announcement_message_unread_lifecycle',
    testCase: 'TC-14',
    summary:
        'announcement message dismissal, replacement, notification route, '
        'and Orbit unread lifecycle',
    groupType: 'announcement',
    senderRole: 'announcement_admin_sender',
    senderPlatform: 'android',
    senderDeviceKind: 'emulator',
    recipientRole: 'announcement_member_recipient',
    recipientPlatform: 'android',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_message',
          'group_type=announcement',
          'relay_store_matched=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_fcm',
        markers: <String>['event=group_message', 'delivery_matched=true'],
      ),
      // Plan 386 / TC-386-02. The relay's own counters, scraped raw before the
      // graded transitions and again after quiescence. This is the only
      // provider evidence relay v1.8.0 can still attribute to this lane.
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay_metrics',
        markers: <String>[
          'MKNOON_386_RELAY_METRICS_PHASE baseline',
          'MKNOON_386_RELAY_METRICS_PHASE final',
          'relay_group_reaction_wake_total',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'role=announcement_admin_sender',
          'two_messages_committed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'role=announcement_member_recipient',
          'route_target_matched=true',
          'conversation_read_committed=true',
          'both_messages_visible=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>['unread=0,1,1,2,0', 'read_commit_before_tap=false'],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_notification_records',
        markers: <String>[
          'dismissal_observed=true',
          'replacement_observed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'ui_automation',
        markers: <String>[
          'orbit=0,1,1,2,0',
          'orbit_indicators_after_return=0',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: 'android_group_reaction_recipient',
    testCase: 'TC-15',
    summary:
        'killed Android target author receives trusted discussion reaction '
        'copy, replacement, target route, and no unread mutation',
    groupType: 'chat',
    senderRole: 'member_reactor',
    senderPlatform: 'android',
    senderDeviceKind: 'emulator',
    recipientRole: 'target_message_author',
    recipientPlatform: 'android',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_reaction',
          'action=add',
          'remove_provider_send=false',
          'duplicate_provider_send=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_fcm',
        markers: <String>['event=group_reaction', 'delivery_matched=true'],
      ),
      // Plan 386 / TC-386-02. The relay's own counters, scraped raw before the
      // graded transitions and again after quiescence. This is the only
      // provider evidence relay v1.8.0 can still attribute to this lane.
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay_metrics',
        markers: <String>[
          'MKNOON_386_RELAY_METRICS_PHASE baseline',
          'MKNOON_386_RELAY_METRICS_PHASE final',
          'relay_group_reaction_wake_total',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'role=member_reactor',
          'group_type=chat',
          'reaction_send_committed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'stored_reaction=true',
          'route_target_matched=true',
          'pid_absent_before_delivery=true',
          'unread_after_tap=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>[
          'reaction_rows=1',
          'reaction_created_message_rows=0',
          'unread=0,0,0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_logcat',
        markers: <String>[
          'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
          'PUSH_ANDROID_DATA_DECRYPT_OK',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_notification_records',
        markers: <String>[
          'title_source=recipient_owned_group',
          'body=Alice reacted to your message',
          'stable_group_card=true',
          'contains_new_message_copy=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'ui_automation',
        markers: <String>[
          'target_message_visible=true',
          'orbit_indicators=0',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: 'android_announcement_reaction_recipient',
    testCase: 'TC-15',
    summary:
        'killed Android announcement author receives trusted member reaction '
        'copy, replacement, target route, and no unread mutation',
    groupType: 'announcement',
    senderRole: 'announcement_member_reactor',
    senderPlatform: 'android',
    senderDeviceKind: 'emulator',
    recipientRole: 'announcement_admin_author',
    recipientPlatform: 'android',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_reaction',
          'action=add',
          'remove_provider_send=false',
          'duplicate_provider_send=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_fcm',
        markers: <String>['event=group_reaction', 'delivery_matched=true'],
      ),
      // Plan 386 / TC-386-02. The relay's own counters, scraped raw before the
      // graded transitions and again after quiescence. This is the only
      // provider evidence relay v1.8.0 can still attribute to this lane.
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay_metrics',
        markers: <String>[
          'MKNOON_386_RELAY_METRICS_PHASE baseline',
          'MKNOON_386_RELAY_METRICS_PHASE final',
          'relay_group_reaction_wake_total',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'role=announcement_member_reactor',
          'group_type=announcement',
          'reaction_send_committed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'role=announcement_admin_author',
          'stored_reaction=true',
          'route_target_matched=true',
          'pid_absent_before_delivery=true',
          'unread_after_tap=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>[
          'reaction_rows=1',
          'reaction_created_message_rows=0',
          'unread=0,0,0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_logcat',
        markers: <String>[
          'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
          'PUSH_ANDROID_DATA_DECRYPT_OK',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_notification_records',
        markers: <String>[
          'title_source=recipient_owned_group',
          'body=Alice reacted to your message',
          'stable_group_card=true',
          'contains_new_message_copy=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'ui_automation',
        markers: <String>[
          'target_message_visible=true',
          'orbit_indicators=0',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: groupReactionBackgroundConnectedScenarioId,
    testCase: 'TC-12',
    summary:
        'backgrounded connected Android target author receives a provably '
        'push-origin discussion reaction while its process stays alive',
    groupType: 'chat',
    senderRole: 'member_reactor',
    senderPlatform: 'android',
    senderDeviceKind: 'emulator',
    recipientRole: 'target_message_author',
    recipientPlatform: 'android',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_reaction',
          'action=add',
          'remove_provider_send=false',
          'duplicate_provider_send=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_fcm',
        markers: <String>['event=group_reaction', 'delivery_matched=true'],
      ),
      // Plan 386 / TC-386-02. The relay's own counters, scraped raw before the
      // graded transitions and again after quiescence. This is the only
      // provider evidence relay v1.8.0 can still attribute to this lane.
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay_metrics',
        markers: <String>[
          'MKNOON_386_RELAY_METRICS_PHASE baseline',
          'MKNOON_386_RELAY_METRICS_PHASE final',
          'relay_group_reaction_wake_total',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'role=member_reactor',
          'group_type=chat',
          'reaction_send_committed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'stored_reaction=true',
          'route_target_matched=true',
          'pid_present_before_delivery=true',
          'connectivity_event=P2P_RELAY_PRESENCE_SET_RESPONSE',
          'home_to_react_delay_ms=3000',
          'notification_observation_window_ms=60000',
          'unread_after_tap=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>[
          'reaction_rows=1',
          'reaction_created_message_rows=0',
          'unread=0,0,0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_logcat',
        markers: <String>[
          'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
          'PUSH_ANDROID_DATA_DECRYPT_OK',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_notification_records',
        markers: <String>[
          'title_source=recipient_owned_group',
          'body=Alice reacted to your message',
          'stable_group_card=true',
          'contains_new_message_copy=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'ui_automation',
        markers: <String>[
          'target_message_visible=true',
          'orbit_indicators=0',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: 'ios_announcement_reaction_recipient',
    testCase: 'TC-16',
    summary:
        'physical iOS announcement author receives NSE reaction copy, one '
        'audible alert, target route, and no unread mutation',
    groupType: 'announcement',
    senderRole: 'announcement_member_reactor',
    senderPlatform: 'android',
    senderDeviceKind: 'physical',
    recipientRole: 'announcement_admin_author',
    recipientPlatform: 'ios',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_reaction',
          'action=add',
          'remove_provider_send=false',
          'duplicate_provider_send=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_apns',
        markers: <String>[
          'event=group_reaction',
          'mutable-content=1',
          'fallback_title=New reaction',
          'fallback_silent=true',
          'provider_private_fields=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'role=announcement_member_reactor',
          'group_type=announcement',
          'reaction_send_committed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'role=announcement_admin_author',
          'stored_reaction=true',
          'route_target_matched=true',
          'unread_after_tap=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>[
          'mknoon.plan257.sqlcipher-observation.v1',
          'reactionRows=1',
          'unreadCount=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'nse_log',
        markers: <String>['PUSH_NSE_DECRYPT_OK', 'kind=group_reaction'],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'xcuitest',
        markers: <String>[
          'testAnnouncementReactionNotificationTap',
          'target_message_visible=true',
          'manual_taps=0',
        ],
      ),
    ],
  ),
];

/// Named source extension consumed only by the Plan-330 Android adapter.
///
/// It deliberately stays out of [groupReactionNotificationScenarios]: the
/// Plan-257 rollout runner and validator own their stable legacy matrix, while
/// Plan 330 has a stronger two-group/media evidence schema and its own Sims
/// capability.
const GroupReactionNotificationScenario
groupNotificationProjectionAndroidSourceScenario =
    GroupReactionNotificationScenario(
      id: 'android_group_notification_projection_durability',
      testCase: 'PLAN-330',
      summary:
          'two-group Android read-zero cancellation plus stable localized '
          'photo, video, and voice-message reaction projection',
      groupType: 'chat',
      senderRole: 'member_reactor',
      senderPlatform: 'android',
      senderDeviceKind: 'emulator',
      recipientRole: 'target_media_author',
      recipientPlatform: 'android',
      recipientDeviceKind: 'physical',
      evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[],
    );

/// Plan 379 muted-group source extensions (G4 closure).
///
/// Like [groupNotificationProjectionAndroidSourceScenario] these deliberately
/// stay out of [groupReactionNotificationScenarios]. The Plan-257 catalog is a
/// *reaction* grammar: its validator hard-requires a non-zero unread count,
/// per-branch notification cards, and relay/provider `[PUSH] … sent to`
/// evidence. A muted group asserts the exact negation of all three, so an
/// in-catalog row could not be expressed without rewriting the six existing
/// scenarios' assertions. The muted lane therefore owns its own validator,
/// runner, and Sims capability and reuses only the shared capture driver.
const GroupReactionNotificationScenario
groupMutedMessageSuppressionSourceScenario = GroupReactionNotificationScenario(
  id: 'android_group_muted_message_suppression',
  testCase: 'PLAN-379',
  summary:
      'muted group suppresses the live-path message card, sound, and badge '
      'while preserving unread and delivery',
  groupType: 'chat',
  senderRole: 'message_sender',
  senderPlatform: 'android',
  senderDeviceKind: 'emulator',
  recipientRole: 'muted_group_member',
  recipientPlatform: 'android',
  recipientDeviceKind: 'physical',
  evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[],
);

const GroupReactionNotificationScenario
groupMutedReactionBackgroundSourceScenario = GroupReactionNotificationScenario(
  id: 'android_group_muted_reaction_background_suppression',
  testCase: 'PLAN-379',
  summary:
      'muted group suppresses the FCM/background-isolate reaction card '
      'while an unmuted control reaction still posts',
  groupType: 'chat',
  senderRole: 'member_reactor',
  senderPlatform: 'android',
  senderDeviceKind: 'emulator',
  recipientRole: 'muted_group_target_author',
  recipientPlatform: 'android',
  recipientDeviceKind: 'physical',
  evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[],
);

/// Plan 384 killed-app group-text source extension (G19 closure).
///
/// Rides the muted lane's runner, pinned pair, and prebuilt APK, but asserts
/// the opposite observable: a card that MUST be present. It therefore owns its
/// own validator kind rather than joining the muted grammar, and it uses the
/// shared capture driver's DEFAULT one-group fixture — no mute toggle, no
/// control group, no reaction.
const GroupReactionNotificationScenario groupTextKilledAppCardSourceScenario =
    GroupReactionNotificationScenario(
      id: 'android_group_text_killed_app_card',
      testCase: 'PLAN-384',
      summary:
          'a killed recipient posts an OS card for a default-lane group text '
          'after a warm-up wake absorbs the cold-start storage deferral',
      groupType: 'chat',
      senderRole: 'message_sender',
      senderPlatform: 'android',
      senderDeviceKind: 'emulator',
      recipientRole: 'killed_app_message_recipient',
      recipientPlatform: 'android',
      recipientDeviceKind: 'physical',
      evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[],
    );

const List<GroupReactionNotificationScenario>
groupMutedNotificationSourceScenarios = <GroupReactionNotificationScenario>[
  groupMutedMessageSuppressionSourceScenario,
  groupMutedReactionBackgroundSourceScenario,
  groupTextKilledAppCardSourceScenario,
];

GroupReactionNotificationScenario? groupReactionNotificationScenario(
  String id,
) {
  if (id == groupNotificationProjectionAndroidSourceScenario.id) {
    return groupNotificationProjectionAndroidSourceScenario;
  }
  for (final scenario in groupMutedNotificationSourceScenarios) {
    if (scenario.id == id) return scenario;
  }
  for (final scenario in groupReactionNotificationScenarios) {
    if (scenario.id == id) return scenario;
  }
  return null;
}

/// Which capture lifecycle a scenario id drives.
enum GroupReactionCaptureLifecycleStage {
  messageUnreadLifecycle,
  reactionRecipient,
  notificationProjection,
  mutedMessageSuppression,
  mutedReactionBackgroundSuppression,
  groupTextKilledAppCard,
}

/// Which SQLCipher probe shape a scenario id asks the installed app for.
///
/// [messageMarkers] sends `firstMarker`/`secondMarker`; the other two send a
/// `targetMarker` only. The in-app probe enforces exactly this split
/// (`group_reaction_e2e_probe.dart` marker-shape gate), so this enum is the
/// harness-side mirror of a contract the runtime already fails closed on.
enum GroupReactionCaptureObservationKind {
  messageMarkers,
  reactionTarget,
  mutedTarget,
}

/// Which artifact validator accepts the capture output for a scenario id.
enum GroupReactionCaptureValidatorKind {
  reaction,
  notificationProjection,
  muted,
  killedTextCard,
}

final class GroupReactionCaptureDispatch {
  const GroupReactionCaptureDispatch({
    required this.lifecycleStage,
    required this.observationKind,
    required this.validatorKind,
  });

  final GroupReactionCaptureLifecycleStage lifecycleStage;
  final GroupReactionCaptureObservationKind observationKind;
  final GroupReactionCaptureValidatorKind validatorKind;
}

/// Resolves the capture driver's per-scenario behaviour from the scenario id.
///
/// The capture driver historically re-derived this at every branch by testing
/// `id.endsWith('_message_unread_lifecycle')`, which silently routes any new
/// id into the reaction branch. Centralizing the decision here makes the
/// routing a host-testable value instead of a string coincidence, and lets a
/// scenario that is neither "message" nor "reaction" exist at all.
///
/// Returns `null` for an unregistered id so callers fail closed.
GroupReactionCaptureDispatch? groupReactionCaptureDispatchFor(
  String scenarioId,
) {
  if (groupReactionNotificationScenario(scenarioId) == null) return null;
  if (scenarioId == groupMutedMessageSuppressionSourceScenario.id) {
    return const GroupReactionCaptureDispatch(
      lifecycleStage:
          GroupReactionCaptureLifecycleStage.mutedMessageSuppression,
      observationKind: GroupReactionCaptureObservationKind.mutedTarget,
      validatorKind: GroupReactionCaptureValidatorKind.muted,
    );
  }
  if (scenarioId == groupMutedReactionBackgroundSourceScenario.id) {
    return const GroupReactionCaptureDispatch(
      lifecycleStage:
          GroupReactionCaptureLifecycleStage.mutedReactionBackgroundSuppression,
      observationKind: GroupReactionCaptureObservationKind.mutedTarget,
      validatorKind: GroupReactionCaptureValidatorKind.muted,
    );
  }
  if (scenarioId == groupTextKilledAppCardSourceScenario.id) {
    // Reuses `mutedTarget`: the in-app probe's marker-shape gate only cares
    // that a single `targetMarker` is sent, which is exactly this lane's
    // shape. A dedicated enum case would have zero consumers.
    return const GroupReactionCaptureDispatch(
      lifecycleStage: GroupReactionCaptureLifecycleStage.groupTextKilledAppCard,
      observationKind: GroupReactionCaptureObservationKind.mutedTarget,
      validatorKind: GroupReactionCaptureValidatorKind.killedTextCard,
    );
  }
  if (scenarioId == groupNotificationProjectionAndroidSourceScenario.id) {
    return const GroupReactionCaptureDispatch(
      lifecycleStage: GroupReactionCaptureLifecycleStage.notificationProjection,
      observationKind: GroupReactionCaptureObservationKind.reactionTarget,
      validatorKind: GroupReactionCaptureValidatorKind.notificationProjection,
    );
  }
  if (scenarioId.endsWith('_message_unread_lifecycle')) {
    return const GroupReactionCaptureDispatch(
      lifecycleStage: GroupReactionCaptureLifecycleStage.messageUnreadLifecycle,
      observationKind: GroupReactionCaptureObservationKind.messageMarkers,
      validatorKind: GroupReactionCaptureValidatorKind.reaction,
    );
  }
  return const GroupReactionCaptureDispatch(
    lifecycleStage: GroupReactionCaptureLifecycleStage.reactionRecipient,
    observationKind: GroupReactionCaptureObservationKind.reactionTarget,
    validatorKind: GroupReactionCaptureValidatorKind.reaction,
  );
}

class GroupReactionNotificationArtifactValidation {
  GroupReactionNotificationArtifactValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;

  String get detail => ok ? 'accepted' : failures.join('; ');
}

Future<GroupReactionNotificationArtifactValidation>
validateGroupReactionNotificationArtifact({
  required String scenario,
  required File artifactFile,
  String? expectedSenderDeviceId,
  String? expectedRecipientDeviceId,
}) async {
  final failures = <String>[];
  final requirement = groupReactionNotificationScenario(scenario);
  if (requirement == null) {
    failures.add(r'$.scenario is not a registered Plan 257 scenario');
    return GroupReactionNotificationArtifactValidation(failures);
  }
  if (!await artifactFile.exists()) {
    failures.add('missing artifact file ${artifactFile.path}');
    return GroupReactionNotificationArtifactValidation(failures);
  }

  late final String raw;
  try {
    raw = await artifactFile.readAsString();
  } on Object {
    failures.add(r'$ artifact could not be read');
    return GroupReactionNotificationArtifactValidation(failures);
  }
  _scanForbidden(raw, r'$', failures);

  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    failures.add(r'$ is not valid JSON');
    return GroupReactionNotificationArtifactValidation(failures);
  }
  final root = _asStringMap(decoded, r'$', failures);
  if (root == null) {
    return GroupReactionNotificationArtifactValidation(failures);
  }

  _expectExactKeys(
    root,
    const <String>{
      'schema',
      'version',
      'scenario',
      'testCase',
      'status',
      'generatedBy',
      'capture',
      'measurements',
      'topology',
      'execution',
      'evidence',
      'redaction',
    },
    r'$',
    failures,
  );
  _expectValue(
    root,
    'schema',
    groupReactionNotificationArtifactSchema,
    r'$',
    failures,
  );
  _expectValue(
    root,
    'version',
    groupReactionNotificationArtifactVersion,
    r'$',
    failures,
  );
  _expectValue(root, 'scenario', scenario, r'$', failures);
  _expectValue(root, 'testCase', requirement.testCase, r'$', failures);
  _expectValue(root, 'status', 'passed', r'$', failures);
  _expectValue(
    root,
    'generatedBy',
    'automated_capture_pipeline',
    r'$',
    failures,
  );

  String? validatedSenderDeviceId;
  String? validatedRecipientDeviceId;
  final topology = _mapField(root, 'topology', r'$', failures);
  if (topology != null) {
    _expectExactKeys(
      topology,
      const <String>{'groupType', 'sender', 'recipient'},
      r'$.topology',
      failures,
    );
    _expectValue(
      topology,
      'groupType',
      requirement.groupType,
      r'$.topology',
      failures,
    );
    final sender = _mapField(topology, 'sender', r'$.topology', failures);
    final recipient = _mapField(topology, 'recipient', r'$.topology', failures);
    final senderId = _validateParty(
      sender,
      path: r'$.topology.sender',
      role: requirement.senderRole,
      platform: requirement.senderPlatform,
      deviceKind: requirement.senderDeviceKind,
      expectedDeviceId: expectedSenderDeviceId,
      failures: failures,
    );
    final recipientId = _validateParty(
      recipient,
      path: r'$.topology.recipient',
      role: requirement.recipientRole,
      platform: requirement.recipientPlatform,
      deviceKind: requirement.recipientDeviceKind,
      expectedDeviceId: expectedRecipientDeviceId,
      failures: failures,
    );
    if (senderId != null && senderId == recipientId) {
      failures.add(r'$.topology sender and recipient device IDs must differ');
    }
    validatedSenderDeviceId = senderId;
    validatedRecipientDeviceId = recipientId;
  }

  final measurements = _mapField(root, 'measurements', r'$', failures);
  _validateMeasurements(
    measurements,
    requirement: requirement,
    failures: failures,
  );

  final capture = _mapField(root, 'capture', r'$', failures);
  await _validateCaptureBundle(
    capture,
    requirement: requirement,
    artifactFile: artifactFile,
    senderDeviceId: validatedSenderDeviceId,
    recipientDeviceId: validatedRecipientDeviceId,
    failures: failures,
  );

  final execution = _mapField(root, 'execution', r'$', failures);
  if (execution != null) {
    _expectExactKeys(
      execution,
      const <String>{
        'automation',
        'manualTaps',
        'forceStopUsed',
        'candidateBuildInstalled',
        'stagingRelay',
        'realProvider',
      },
      r'$.execution',
      failures,
    );
    _expectValue(
      execution,
      'automation',
      'fully_automated',
      r'$.execution',
      failures,
    );
    _expectValue(execution, 'manualTaps', 0, r'$.execution', failures);
    _expectValue(execution, 'forceStopUsed', false, r'$.execution', failures);
    _expectValue(
      execution,
      'candidateBuildInstalled',
      true,
      r'$.execution',
      failures,
    );
    _expectValue(execution, 'stagingRelay', true, r'$.execution', failures);
    _expectValue(execution, 'realProvider', true, r'$.execution', failures);
  }

  final redaction = _mapField(root, 'redaction', r'$', failures);
  if (redaction != null) {
    _expectExactKeys(
      redaction,
      const <String>{
        'pushTokensPersisted',
        'secretKeysPersisted',
        'ciphertextPersisted',
        'plaintextPayloadPersisted',
        'rawPeerIdsPersisted',
      },
      r'$.redaction',
      failures,
    );
    for (final key in const <String>[
      'pushTokensPersisted',
      'secretKeysPersisted',
      'ciphertextPersisted',
      'plaintextPayloadPersisted',
      'rawPeerIdsPersisted',
    ]) {
      _expectValue(redaction, key, false, r'$.redaction', failures);
    }
  }

  await _validateEvidence(
    root['evidence'],
    requirement: requirement,
    artifactFile: artifactFile,
    measurements: measurements,
    failures: failures,
  );
  return GroupReactionNotificationArtifactValidation(failures);
}

Future<File> writeGroupReactionNotificationVerdict({
  required Directory outputDirectory,
  required String scenario,
  required bool ok,
  required String stage,
  required String status,
  required String detail,
}) async {
  await outputDirectory.create(recursive: true);
  final file = File(
    '${outputDirectory.path}${Platform.pathSeparator}'
    '${scenario}_orchestrator_verdict.json',
  );
  await file.writeAsString(
    jsonEncode(<String, Object?>{
      'schema': groupReactionNotificationVerdictSchema,
      'version': 1,
      'scenario': scenario,
      'ok': ok,
      'stage': stage,
      'status': status,
      'detail': detail,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
    }),
    flush: true,
  );
  return file;
}

String? _validateParty(
  Map<String, Object?>? party, {
  required String path,
  required String role,
  required String platform,
  required String deviceKind,
  required String? expectedDeviceId,
  required List<String> failures,
}) {
  if (party == null) return null;
  _expectExactKeys(
    party,
    const <String>{
      'role',
      'platform',
      'deviceKind',
      'deviceId',
      'liveDiscovered',
      'explicitId',
    },
    path,
    failures,
  );
  _expectValue(party, 'role', role, path, failures);
  _expectValue(party, 'platform', platform, path, failures);
  _expectValue(party, 'deviceKind', deviceKind, path, failures);
  _expectValue(party, 'liveDiscovered', true, path, failures);
  _expectValue(party, 'explicitId', true, path, failures);
  final deviceId = _requiredString(party, 'deviceId', path, failures);
  if (deviceId == null) return null;
  if (!RegExp(r'^[A-Za-z0-9._:-]{4,128}$').hasMatch(deviceId)) {
    failures.add('$path.deviceId is not a safe explicit device ID');
  }
  final looksLikeEmulator = RegExp(r'^emulator-[0-9]+$').hasMatch(deviceId);
  final looksLikePhysicalIos = RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$',
  ).hasMatch(deviceId);
  if (deviceKind == 'emulator' && !looksLikeEmulator) {
    failures.add('$path.deviceId must identify an Android emulator');
  }
  if (deviceKind == 'physical' && looksLikeEmulator) {
    failures.add('$path.deviceId must identify a physical device');
  }
  if (platform == 'ios' && !looksLikePhysicalIos) {
    failures.add('$path.deviceId must identify a physical iOS device');
  }
  if (platform == 'android' && looksLikePhysicalIos) {
    failures.add('$path.deviceId must identify an Android device');
  }
  if (expectedDeviceId != null && deviceId != expectedDeviceId) {
    failures.add('$path.deviceId does not match the explicit runner device');
  }
  return deviceId;
}

Future<void> _validateEvidence(
  Object? value, {
  required GroupReactionNotificationScenario requirement,
  required File artifactFile,
  required Map<String, Object?>? measurements,
  required List<String> failures,
}) async {
  if (value is! List) {
    failures.add(r'$.evidence must be a list');
    return;
  }
  final requiredByKind = <String, GroupReactionNotificationEvidenceRequirement>{
    for (final evidence in requirement.evidenceRequirements)
      evidence.kind: evidence,
  };
  final recordsByKind = <String, Map<String, Object?>>{};
  for (var index = 0; index < value.length; index++) {
    final path = '\$.evidence[$index]';
    final record = _asStringMap(value[index], path, failures);
    if (record == null) continue;
    _expectExactKeys(
      record,
      const <String>{'kind', 'path', 'sha256', 'bytes'},
      path,
      failures,
    );
    final kind = _requiredString(record, 'kind', path, failures);
    if (kind == null) continue;
    if (!requiredByKind.containsKey(kind)) {
      failures.add('$path.kind is not required for ${requirement.id}');
      continue;
    }
    if (recordsByKind.containsKey(kind)) {
      failures.add('$path.kind duplicates evidence kind $kind');
      continue;
    }
    recordsByKind[kind] = record;
  }

  for (final kind in requiredByKind.keys) {
    if (!recordsByKind.containsKey(kind)) {
      failures.add('\$.evidence is missing required kind $kind');
    }
  }

  final artifactDirectory = await artifactFile.parent.resolveSymbolicLinks();
  final evidenceTexts = <String, String>{};
  for (final entry in recordsByKind.entries) {
    final record = entry.value;
    final path = '\$.evidence[${entry.key}]';
    final rawPath = _requiredString(record, 'path', path, failures);
    final expectedSha = _requiredString(record, 'sha256', path, failures);
    final expectedBytes = record['bytes'];
    if (expectedBytes is! int || expectedBytes <= 0) {
      failures.add('$path.bytes must be a positive integer');
    }
    if (expectedSha == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha)) {
      failures.add('$path.sha256 must be a lowercase SHA-256 digest');
    }
    if (rawPath == null) continue;
    final segments = rawPath.split(RegExp(r'[/\\]'));
    if (File(rawPath).isAbsolute || segments.contains('..')) {
      failures.add('$path.path must stay inside the artifact directory');
      continue;
    }
    final evidenceFile = File(
      '${artifactFile.parent.path}${Platform.pathSeparator}$rawPath',
    );
    if (!await evidenceFile.exists()) {
      failures.add('$path.path is missing');
      continue;
    }
    final resolved = await evidenceFile.resolveSymbolicLinks();
    if (!resolved.startsWith('$artifactDirectory${Platform.pathSeparator}')) {
      failures.add('$path.path must stay inside the artifact directory');
      continue;
    }
    final bytes = await evidenceFile.readAsBytes();
    if (expectedBytes is int && bytes.length != expectedBytes) {
      failures.add('$path.bytes does not match the evidence file');
    }
    if (expectedSha != null &&
        sha256.convert(bytes).toString() != expectedSha) {
      failures.add('$path SHA-256 mismatch');
    }
    late final String text;
    try {
      text = utf8.decode(bytes);
    } on Object {
      failures.add('$path is not UTF-8 evidence');
      continue;
    }
    _scanForbidden(text, path, failures);
    evidenceTexts[entry.key] = text;
  }

  _validateAuthoritativeEvidence(
    requirement: requirement,
    measurements: measurements,
    evidenceTexts: evidenceTexts,
    failures: failures,
  );
}

void _validateMeasurements(
  Map<String, Object?>? measurements, {
  required GroupReactionNotificationScenario requirement,
  required List<String> failures,
}) {
  if (measurements == null) return;
  _expectExactKeys(
    measurements,
    const <String>{
      'appPackage',
      'groupName',
      'actorName',
      'firstMarker',
      'secondMarker',
      'targetMarker',
      'expectedRelayWakeAttempts',
    },
    r'$.measurements',
    failures,
  );
  _requiredString(measurements, 'appPackage', r'$.measurements', failures);
  _requiredString(measurements, 'groupName', r'$.measurements', failures);
  _requiredString(measurements, 'actorName', r'$.measurements', failures);
  for (final key in const <String>[
    'firstMarker',
    'secondMarker',
    'targetMarker',
  ]) {
    if (measurements[key] is! String) {
      failures.add('\$.measurements.$key must be a string');
    }
  }
  _expectValue(
    measurements,
    'expectedRelayWakeAttempts',
    2,
    r'$.measurements',
    failures,
  );
  final messageScenario = requirement.id.endsWith('_message_unread_lifecycle');
  final first = measurements['firstMarker'];
  final second = measurements['secondMarker'];
  final target = measurements['targetMarker'];
  if (messageScenario) {
    if (first is! String ||
        first.isEmpty ||
        second is! String ||
        second.isEmpty) {
      failures.add(
        r'$.measurements message lifecycle requires first/second markers',
      );
    }
    if (target != '') {
      failures.add(r'$.measurements.targetMarker must be empty for messages');
    }
  } else {
    if (target is! String || target.isEmpty) {
      failures.add(r'$.measurements reaction lifecycle requires targetMarker');
    }
    if (first != '' || second != '') {
      failures.add(
        r'$.measurements first/second markers must be empty for reactions',
      );
    }
  }
}

Future<void> _validateCaptureBundle(
  Map<String, Object?>? capture, {
  required GroupReactionNotificationScenario requirement,
  required File artifactFile,
  required String? senderDeviceId,
  required String? recipientDeviceId,
  required List<String> failures,
}) async {
  if (capture == null) return;
  _expectExactKeys(
    capture,
    const <String>{'configuration', 'candidateBuild', 'commandJournal'},
    r'$.capture',
    failures,
  );
  final configuration = await _readReferencedText(
    capture['configuration'],
    artifactFile: artifactFile,
    path: r'$.capture.configuration',
    failures: failures,
  );
  final candidateBuild = await _readReferencedText(
    capture['candidateBuild'],
    artifactFile: artifactFile,
    path: r'$.capture.candidateBuild',
    failures: failures,
  );
  final commandJournal = await _readReferencedText(
    capture['commandJournal'],
    artifactFile: artifactFile,
    path: r'$.capture.commandJournal',
    failures: failures,
  );

  if (configuration != null) {
    final value = _decodeObject(
      configuration,
      r'$.capture.configuration',
      failures,
    );
    if (value != null) {
      if (value['schema'] != 'mknoon.plan257.configuration-verdict.v1' ||
          value['scenario'] != requirement.id ||
          value['ok'] != true ||
          value['environment'] != 'staging' ||
          value['productionDeploymentPerformed'] != false) {
        failures.add(
          r'$.capture.configuration is not an accepted staging verdict',
        );
      }
      final sender = value['sender'];
      final recipient = value['recipient'];
      if (sender is! Map || sender['deviceId'] != senderDeviceId) {
        failures.add(
          r'$.capture.configuration sender does not bind topology device',
        );
      }
      if (recipient is! Map || recipient['deviceId'] != recipientDeviceId) {
        failures.add(
          r'$.capture.configuration recipient does not bind topology device',
        );
      }
      final relay = value['relay'];
      final provider = value['provider'];
      if (relay is! Map ||
          relay['active'] != true ||
          relay['candidateRevisionMatched'] != true ||
          relay['groupReactionRolloutEnabled'] != true ||
          provider is! Map ||
          provider['configurationChecked'] != true) {
        failures.add(
          r'$.capture.configuration lacks live relay/provider qualification',
        );
      }
    }
  }

  var centralPrebuiltAndroid = false;
  var parentPreparedCentralPrebuiltAndroid = false;
  if (candidateBuild != null) {
    final value = _decodeObject(
      candidateBuild,
      r'$.capture.candidateBuild',
      failures,
    );
    if (value != null) {
      final e2eSha256 = value['e2eApkSha256'];
      final normalSha256 = value['normalApkSha256'];
      final sourceProvenance = value['sourceProvenance'];
      centralPrebuiltAndroid =
          requirement.recipientPlatform == 'android' &&
          value['buildMode'] == 'central_prebuilt' &&
          value['buildProfile'] == 'android.production_fcm' &&
          value['childBuildCount'] == 0 &&
          value['parentPreparedAndroidState'] is bool &&
          _isSha256(e2eSha256) &&
          e2eSha256 == normalSha256 &&
          sourceProvenance ==
              'central-prebuilt:android.production_fcm:$e2eSha256';
      parentPreparedCentralPrebuiltAndroid =
          centralPrebuiltAndroid && value['parentPreparedAndroidState'] == true;
      final legacyDistinctBuild =
          _isSha256(e2eSha256) &&
          _isSha256(normalSha256) &&
          e2eSha256 != normalSha256 &&
          sourceProvenance is String &&
          sourceProvenance.contains('+worktree:');
      if (value['schema'] != 'mknoon.plan257.candidate-build.v1' ||
          (!legacyDistinctBuild && !centralPrebuiltAndroid)) {
        failures.add(
          r'$.capture.candidateBuild lacks accepted legacy-distinct or '
          'central-prebuilt candidate provenance',
        );
      }
      if (requirement.recipientPlatform == 'ios') {
        final e2eAppSha = value['iosE2eAppSha256'];
        final normalAppSha = value['iosNormalAppSha256'];
        if (value['iosBundleId'] != 'com.mknoon.app' ||
            value['iosBuildTarget'] != 'build/ios/iphoneos/Runner.app' ||
            !_isSha256(e2eAppSha) ||
            !_isSha256(normalAppSha) ||
            e2eAppSha == normalAppSha ||
            value['iosInstallReceipts'] is! List) {
          failures.add(
            r'$.capture.candidateBuild lacks distinct signed physical-iOS '
            'bundle provenance',
          );
        } else {
          final receipts = value['iosInstallReceipts'] as List;
          final seenModes = <String>{};
          if (receipts.length != 2) {
            failures.add(
              r'$.capture.candidateBuild must bind two physical-iOS install '
              'receipts',
            );
          }
          for (var index = 0; index < receipts.length; index++) {
            final record = _asStringMap(
              receipts[index],
              '\$.capture.candidateBuild.iosInstallReceipts[$index]',
              failures,
            );
            if (record == null) continue;
            _expectExactKeys(
              record,
              const <String>{'mode', 'receipt'},
              '\$.capture.candidateBuild.iosInstallReceipts[$index]',
              failures,
            );
            final mode = _requiredString(
              record,
              'mode',
              '\$.capture.candidateBuild.iosInstallReceipts[$index]',
              failures,
            );
            if (mode == null ||
                !const <String>{'e2e', 'normal'}.contains(mode) ||
                !seenModes.add(mode)) {
              failures.add(
                r'$.capture.candidateBuild has invalid/duplicate iOS install '
                'receipt mode',
              );
            }
            final receipt = await _readReferencedText(
              record['receipt'],
              artifactFile: artifactFile,
              path:
                  '\$.capture.candidateBuild.iosInstallReceipts[$index].receipt',
              failures: failures,
            );
            if (receipt == null ||
                !receipt.contains('com.mknoon.app') ||
                (recipientDeviceId != null &&
                    !receipt.contains(recipientDeviceId))) {
              failures.add(
                r'$.capture.candidateBuild iOS install receipt does not bind '
                'the selected device and bundle',
              );
            }
          }
          if (!seenModes.containsAll(const <String>{'e2e', 'normal'})) {
            failures.add(
              r'$.capture.candidateBuild lacks e2e/normal iOS install receipts',
            );
          }
        }
      }
    }
  }

  if (commandJournal != null) {
    final value = _decodeObject(
      commandJournal,
      r'$.capture.commandJournal',
      failures,
    );
    if (value != null) {
      if (value['schema'] != 'mknoon.plan257.command-journal.v1' ||
          value['scenario'] != requirement.id ||
          value['commands'] is! List) {
        failures.add(r'$.capture.commandJournal has the wrong schema/scenario');
      } else {
        final commands = (value['commands'] as List)
            .whereType<Map>()
            .map((entry) => Map<String, Object?>.from(entry))
            .toList(growable: false);
        _validateCommandJournal(
          commands,
          requirement: requirement,
          senderDeviceId: senderDeviceId,
          recipientDeviceId: recipientDeviceId,
          centralPrebuiltAndroid: centralPrebuiltAndroid,
          parentPreparedCentralPrebuiltAndroid:
              parentPreparedCentralPrebuiltAndroid,
          failures: failures,
        );
      }
    }
  }
}

void _validateCommandJournal(
  List<Map<String, Object?>> commands, {
  required GroupReactionNotificationScenario requirement,
  required String? senderDeviceId,
  required String? recipientDeviceId,
  required bool centralPrebuiltAndroid,
  required bool parentPreparedCentralPrebuiltAndroid,
  required List<String> failures,
}) {
  bool hasCommand(String stage, String executable, String argumentFragment) {
    return commands.any((command) {
      if (command['stage'] != stage || command['executable'] != executable) {
        return false;
      }
      final args = command['args'];
      return args is List &&
          args.any((argument) => '$argument'.contains(argumentFragment));
    });
  }

  bool hasSuccessfulAdbCommand(
    String stage,
    String deviceId,
    Set<String> requiredArguments,
  ) {
    return commands.any((command) {
      final args = command['args'];
      return command['stage'] == stage &&
          command['executable'] == 'adb' &&
          command['exitCode'] == 0 &&
          args is List &&
          args.contains(deviceId) &&
          requiredArguments.every(args.contains);
    });
  }

  bool isInstallCommand(Map<String, Object?> command) {
    final args = command['args'];
    return args is List &&
        (args.contains('install') || args.contains('install-multiple'));
  }

  for (final command in commands) {
    if (command['stage'] is! String ||
        command['executable'] is! String ||
        command['args'] is! List ||
        command['exitCode'] is! int ||
        DateTime.tryParse('${command['recordedAt']}') == null) {
      failures.add(r'$.capture.commandJournal contains a malformed command');
      break;
    }
  }
  final childBuildCommands = commands.where(
    (command) =>
        (command['stage'] == 'candidate_build' ||
            command['stage'] == 'ios_android_sender_build') &&
        command['executable'] == 'flutter' &&
        (command['args'] as List).contains('build'),
  );
  final buildBoundary = centralPrebuiltAndroid
      ? childBuildCommands.isEmpty
      : childBuildCommands.length >= 2;
  final roleInstallCommands = commands.where(
    (command) =>
        command['stage'] ==
            (requirement.recipientPlatform == 'ios'
                ? 'ios_android_sender_build'
                : 'android_role_install') &&
        command['executable'] == 'adb' &&
        isInstallCommand(command),
  );
  final parentPreparedRoleBoundary =
      parentPreparedCentralPrebuiltAndroid &&
      senderDeviceId != null &&
      recipientDeviceId != null &&
      <String>[senderDeviceId, recipientDeviceId].every(
        (deviceId) =>
            hasSuccessfulAdbCommand(
              'android_role_install',
              deviceId,
              const <String>{'shell', 'pm', 'path', 'com.mknoon.app'},
            ) &&
            hasSuccessfulAdbCommand(
              'android_role_install',
              deviceId,
              const <String>{'shell', 'sha256sum'},
            ),
      ) &&
      roleInstallCommands.isEmpty;
  final roleBoundary = parentPreparedCentralPrebuiltAndroid
      ? parentPreparedRoleBoundary
      : roleInstallCommands.isNotEmpty;
  final hasCommonBoundaryCommands =
      hasCommand('device_inventory', 'flutter', 'devices') &&
      hasCommand('device_inventory', 'adb', 'devices') &&
      hasCommand('relay_configuration', 'ssh', 'systemctl') &&
      buildBoundary &&
      roleBoundary;
  if (!hasCommonBoundaryCommands) {
    failures.add(
      r'$.capture.commandJournal is missing common inventory/relay/build/'
      'Android-role preparation boundary commands',
    );
  }
  if (parentPreparedCentralPrebuiltAndroid && !parentPreparedRoleBoundary) {
    failures.add(
      r'$.capture.commandJournal must contain successful both-device pm path '
      'and SHA-256 verification at android_role_install, with no redundant '
      'install for parent-prepared central-prebuilt Android state',
    );
  }
  for (final deviceId in <String?>[senderDeviceId, recipientDeviceId]) {
    if (deviceId != null &&
        !commands.any(
          (command) =>
              command['args'] is List &&
              (command['args'] as List).contains(deviceId),
        )) {
      failures.add(
        r'$.capture.commandJournal does not bind explicit device ' + deviceId,
      );
    }
  }
  if (requirement.recipientPlatform == 'ios') {
    const selectorFragments = <String>[
      'testCreateAnnouncementReactionFixture',
      'testAuthorAnnouncementReactionTarget',
      'testPrepareWarmNotificationTap',
      'testAnnouncementReactionNotificationTap',
    ];
    final missingSelector = selectorFragments.any(
      (selector) => !commands.any(
        (command) =>
            command['executable'] == 'xcodebuild' &&
            command['args'] is List &&
            (command['args'] as List).any(
              (argument) => '$argument'.contains(selector),
            ),
      ),
    );
    final iosInstallCommands = commands
        .where(
          (command) =>
              command['stage'] == 'ios_candidate_install' &&
              command['executable'] == 'xcrun' &&
              command['args'] is List &&
              (command['args'] as List).contains('install'),
        )
        .length;
    if (!hasCommand('ios_candidate_build', 'flutter', 'ios') ||
        iosInstallCommands < 2 ||
        !hasCommand('ios_fixture_staging', 'xcrun', 'copy') ||
        !hasCommand(
          'ios_system_log',
          'idevicesyslog',
          recipientDeviceId ?? '',
        ) ||
        !hasCommand('sqlcipher_observation', 'flutter', _plan257SqlProbe) ||
        missingSelector) {
      failures.add(
        r'$.capture.commandJournal lacks physical iOS build/install/container/'
        'syslog/SQLCipher or named XCUITest boundary commands',
      );
    }
    final lifecycleCommands = commands
        .where((command) => command['stage'] == 'ios_reaction_lifecycle')
        .toList(growable: false);
    if (lifecycleCommands.isEmpty ||
        !lifecycleCommands.any(
          (command) =>
              command['executable'] == 'adb' &&
              (command['args'] as List).contains('input'),
        )) {
      failures.add(
        r'$.capture.commandJournal lacks automated iOS-bound reaction UI '
        'commands',
      );
    }
    if (lifecycleCommands.any(
      (command) => (command['args'] as List).contains('force-stop'),
    )) {
      failures.add(
        r'$.capture.commandJournal used force-stop inside the proof window',
      );
    }
    return;
  }

  final hasSqlCipherBoundary = centralPrebuiltAndroid
      ? hasCommand(
          'sqlcipher_observation',
          'adb',
          'plan257_intro_e2e_config.json',
        )
      : hasCommand('sqlcipher_observation', 'flutter', _plan257SqlProbe);
  final providerInstallCommands = commands.where(
    (command) =>
        command['stage'] == 'provider_registration' &&
        command['executable'] == 'adb' &&
        isInstallCommand(command),
  );
  final providerBoundary = parentPreparedCentralPrebuiltAndroid
      ? recipientDeviceId != null &&
            providerInstallCommands.isEmpty &&
            hasSuccessfulAdbCommand(
              'provider_registration',
              recipientDeviceId,
              const <String>{
                'shell',
                'am',
                'start',
                'com.mknoon.app/.MainActivity',
              },
            )
      : providerInstallCommands.isNotEmpty;
  if (!providerBoundary || !hasSqlCipherBoundary) {
    failures.add(
      r'$.capture.commandJournal is missing Android provider/SQLCipher '
      'boundary commands',
    );
  }
  if (parentPreparedCentralPrebuiltAndroid &&
      providerInstallCommands.isNotEmpty) {
    failures.add(
      r'$.capture.commandJournal contains a forbidden provider reinstall for '
      'parent-prepared central-prebuilt Android state',
    );
  }
  if (centralPrebuiltAndroid &&
      commands.any(
        (command) =>
            command['executable'] == 'flutter' &&
            command['args'] is List &&
            (command['args'] as List).any(
              (argument) => '$argument'.contains(_plan257SqlProbe),
            ),
      )) {
    failures.add(
      r'$.capture.commandJournal contains a forbidden child Flutter '
      'SQLCipher probe for a central-prebuilt Android run',
    );
  }

  final lifecycleStage = requirement.id.endsWith('_message_unread_lifecycle')
      ? 'android_unread_lifecycle'
      : 'android_reaction_lifecycle';
  final processAliveReaction = _processAliveReactionScenarioIds.contains(
    requirement.id,
  );
  final lifecycleCommands = commands
      .where((command) => command['stage'] == lifecycleStage)
      .toList(growable: false);
  if (lifecycleCommands.isEmpty ||
      !lifecycleCommands.any(
        (command) =>
            command['executable'] == 'adb' &&
            (command['args'] as List).contains('input'),
      )) {
    failures.add(
      r'$.capture.commandJournal lacks automated lifecycle UI commands',
    );
  }
  if (lifecycleCommands.any(
    (command) => (command['args'] as List).contains('force-stop'),
  )) {
    failures.add(
      r'$.capture.commandJournal used force-stop inside the proof window',
    );
  }
  if (!requirement.id.endsWith('_message_unread_lifecycle') &&
      !processAliveReaction &&
      (!lifecycleCommands.any(
            (command) => (command['args'] as List).contains('kill'),
          ) ||
          !lifecycleCommands.any(
            (command) => (command['args'] as List).contains('pidof'),
          ))) {
    failures.add(
      r'$.capture.commandJournal lacks killed-process/pidof reaction proof',
    );
  }
  if (processAliveReaction) {
    final homeIndex = lifecycleCommands.indexWhere((command) {
      final args = command['args'] as List;
      return command['executable'] == 'adb' &&
          command['exitCode'] == 0 &&
          (recipientDeviceId == null || args.contains(recipientDeviceId)) &&
          args.contains('input') &&
          args.contains('KEYCODE_HOME');
    });
    final pidIndex = lifecycleCommands.indexWhere((command) {
      final args = command['args'] as List;
      return command['executable'] == 'adb' &&
          command['exitCode'] == 0 &&
          (recipientDeviceId == null || args.contains(recipientDeviceId)) &&
          args.contains('pidof');
    }, homeIndex < 0 ? 0 : homeIndex + 1);
    final usedProcessTermination = lifecycleCommands.any((command) {
      final args = command['args'] as List;
      return args.contains('kill') || args.contains('stop-app');
    });
    if (homeIndex < 0 || pidIndex <= homeIndex || usedProcessTermination) {
      failures.add(
        r'$.capture.commandJournal lacks ordered HOME/pidof process-alive '
        'reaction proof or contains process termination',
      );
    }
  }
  if (!requirement.id.endsWith('_message_unread_lifecycle') &&
      !processAliveReaction) {
    if (centralPrebuiltAndroid) {
      final runtimeProbeIndex = commands.indexWhere(
        (command) =>
            command['stage'] == lifecycleStage &&
            command['executable'] == 'adb' &&
            command['exitCode'] == 0 &&
            command['args'] is List &&
            (command['args'] as List).any(
              (argument) =>
                  '$argument'.contains('plan257_intro_e2e_config.json'),
            ),
      );
      final productionStartIndex = runtimeProbeIndex < 0
          ? -1
          : commands.indexWhere(
              (command) =>
                  command['stage'] == lifecycleStage &&
                  command['executable'] == 'adb' &&
                  command['exitCode'] == 0 &&
                  command['args'] is List &&
                  (command['args'] as List).contains('am') &&
                  (command['args'] as List).contains('start') &&
                  (command['args'] as List).any(
                    (argument) =>
                        '$argument'.contains('com.mknoon.app/.MainActivity'),
                  ),
              runtimeProbeIndex + 1,
            );
      final forbiddenChildProbe = commands.any(
        (command) =>
            command['executable'] == 'flutter' &&
            command['args'] is List &&
            (command['args'] as List).any(
              (argument) => '$argument'.contains(_plan257SqlProbe),
            ),
      );
      if (runtimeProbeIndex < 0 ||
          productionStartIndex <= runtimeProbeIndex ||
          forbiddenChildProbe) {
        failures.add(
          r'$.capture.commandJournal lacks the installed-app exact-ADD '
          'runtime probe and production retry launch, or contains a '
          'forbidden child Flutter probe',
        );
      }
      return;
    }
    final duplicateProbeIndex = commands.indexWhere(
      (command) =>
          command['stage'] == lifecycleStage &&
          command['executable'] == 'flutter' &&
          command['exitCode'] == 0 &&
          command['args'] is List &&
          (command['args'] as List).any(
            (argument) => '$argument'.contains(_plan257SqlProbe),
          ) &&
          (command['args'] as List).contains('drive') &&
          (command['args'] as List).contains('--keep-app-running') &&
          (command['args'] as List).contains(
            'test_driver/integration_test.dart',
          ),
    );
    final normalReinstallIndex = commands.indexWhere(
      (command) =>
          command['stage'] == lifecycleStage &&
          command['executable'] == 'adb' &&
          command['exitCode'] == 0 &&
          command['args'] is List &&
          (command['args'] as List).contains('install') &&
          (command['args'] as List).any(
            (argument) => '$argument'.contains('candidate_normal_arm64.apk'),
          ),
    );
    final productionStartIndex = normalReinstallIndex < 0
        ? -1
        : commands.indexWhere(
            (command) =>
                command['stage'] == lifecycleStage &&
                command['executable'] == 'adb' &&
                command['exitCode'] == 0 &&
                command['args'] is List &&
                (command['args'] as List).contains('shell') &&
                (command['args'] as List).contains('am') &&
                (command['args'] as List).contains('start') &&
                (command['args'] as List).any(
                  (argument) =>
                      '$argument'.contains('com.mknoon.app/.MainActivity'),
                ),
            normalReinstallIndex + 1,
          );
    if (duplicateProbeIndex < 0 ||
        normalReinstallIndex <= duplicateProbeIndex ||
        productionStartIndex <= normalReinstallIndex) {
      failures.add(
        r'$.capture.commandJournal lacks ordered exact-ADD probe and '
        'production retry launch commands',
      );
    }
  }
}

const String _plan257SqlProbe =
    'group_reaction_notification_sqlcipher_probe_test.dart';
const String _plan257DuplicateRedrivePrefix =
    'MKNOON_257_DUPLICATE_REDRIVE_OBSERVATION ';

Future<String?> _readReferencedText(
  Object? rawReference, {
  required File artifactFile,
  required String path,
  required List<String> failures,
}) async {
  final reference = _asStringMap(rawReference, path, failures);
  if (reference == null) return null;
  _expectExactKeys(
    reference,
    const <String>{'path', 'sha256', 'bytes'},
    path,
    failures,
  );
  final relativePath = _requiredString(reference, 'path', path, failures);
  final expectedSha = _requiredString(reference, 'sha256', path, failures);
  final expectedBytes = reference['bytes'];
  if (relativePath == null) return null;
  final segments = relativePath.split(RegExp(r'[/\\]'));
  if (File(relativePath).isAbsolute || segments.contains('..')) {
    failures.add('$path.path must stay inside the artifact directory');
    return null;
  }
  final file = File(
    '${artifactFile.parent.path}${Platform.pathSeparator}$relativePath',
  );
  if (!await file.exists()) {
    failures.add('$path.path is missing');
    return null;
  }
  final artifactDirectory = await artifactFile.parent.resolveSymbolicLinks();
  final resolved = await file.resolveSymbolicLinks();
  if (!resolved.startsWith('$artifactDirectory${Platform.pathSeparator}')) {
    failures.add('$path.path must stay inside the artifact directory');
    return null;
  }
  final bytes = await file.readAsBytes();
  if (expectedBytes is! int ||
      expectedBytes <= 0 ||
      bytes.length != expectedBytes) {
    failures.add('$path.bytes does not match a positive evidence length');
  }
  if (!_isSha256(expectedSha) ||
      sha256.convert(bytes).toString() != expectedSha) {
    failures.add('$path SHA-256 mismatch');
  }
  try {
    final text = utf8.decode(bytes);
    _scanForbidden(text, path, failures);
    return text;
  } on Object {
    failures.add('$path is not UTF-8 evidence');
    return null;
  }
}

Map<String, Object?>? _decodeObject(
  String raw,
  String path,
  List<String> failures,
) {
  try {
    final value = jsonDecode(raw);
    return _asStringMap(value, path, failures);
  } on Object {
    failures.add('$path is not valid JSON');
    return null;
  }
}

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

void _validateAuthoritativeEvidence({
  required GroupReactionNotificationScenario requirement,
  required Map<String, Object?>? measurements,
  required Map<String, String> evidenceTexts,
  required List<String> failures,
}) {
  if (measurements == null) return;
  if (requirement.recipientPlatform == 'ios') {
    _validateIosAuthoritativeEvidence(
      requirement: requirement,
      measurements: measurements,
      evidenceTexts: evidenceTexts,
      failures: failures,
    );
    return;
  }
  final groupName = measurements['groupName'] as String? ?? '';
  final actorName = measurements['actorName'] as String? ?? '';
  final appPackage = measurements['appPackage'] as String? ?? '';
  final expectedRelayWakeAttempts =
      measurements['expectedRelayWakeAttempts'] as int? ?? -1;
  final relay = evidenceTexts['relay'] ?? '';
  final provider = evidenceTexts['provider_fcm'] ?? '';
  final senderApp = evidenceTexts['sender_app'] ?? '';
  final recipientApp = evidenceTexts['recipient_app'] ?? '';
  final androidLogcat = evidenceTexts['android_logcat'] ?? '';
  final sqlCipher = evidenceTexts['sqlcipher_state'] ?? '';
  final notificationRecords =
      evidenceTexts['android_notification_records'] ?? '';
  final uiAutomation = evidenceTexts['ui_automation'] ?? '';

  final rawRelayLines = relay
      .split('\n')
      .where(
        (line) =>
            line.contains('[GROUP_INBOX]') ||
            line.contains('[PUSH]') ||
            line.contains('[GROUP_REACTION_WAKE]'),
      )
      .toList(growable: false);
  if (rawRelayLines.isEmpty ||
      rawRelayLines.any(
        (line) => !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(line),
      ) ||
      !rawRelayLines.any(
        (line) => line.contains('[GROUP_INBOX] Stored message for group'),
      )) {
    failures.add(r'$.evidence[relay] is not raw timestamped relay custody');
  }
  final messageScenario = requirement.id.endsWith('_message_unread_lifecycle');
  final processAliveReaction = _processAliveReactionScenarioIds.contains(
    requirement.id,
  );
  // TC-386-03. Relay v1.8.0 emits `[GROUP_REACTION_WAKE] outcome=<word>` and
  // nothing else: the `remote_type=` attribute this used to require was deleted
  // with the rest of the attributed `[PUSH]`/wake vocabulary by `8d86501e4`, so
  // the old conjunct rejected every real journal. `outcome=dispatched` is the
  // line the relay prints once per recipient it actually hands to the provider
  // (`go-relay-server/inbox.go:2797`), which is the same discrimination the old
  // attribute carried. The recipient-side push-origin marker is unchanged and
  // still required, so this stays a three-way discrimination.
  if (processAliveReaction &&
      (!rawRelayLines.any(
            (line) =>
                line.contains('[GROUP_REACTION_WAKE]') &&
                line.contains('outcome=dispatched'),
          ) ||
          !provider.contains('event=group_reaction') ||
          !provider.contains('delivery_matched=true') ||
          !androidLogcat.contains(
            'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
          ))) {
    failures.add(
      r'$.evidence background-connected reaction lacks relay/provider/logcat '
      'push-origin discrimination',
    );
  }

  // TC-386-01/04. Qualitative half: the relay journal must record a real
  // provider acceptance in the capture window. The predicate is Plan 380 W0's,
  // imported rather than re-derived, so exactly one definition of the v1.8.0
  // acceptance grammar exists in the repository.
  if (!relayJournalContainsAndroidProviderSend(provider)) {
    failures.add(
      r'$.evidence[provider_fcm] records no v1.8.0 provider acceptance',
    );
  }

  // TC-386-02. Quantitative half: an exact RELAY COUNTER DELTA, per lane.
  //
  // Counting journal lines cannot work on v1.8.0. What survives is
  // `[PUSH] outcome=success attempt=N total_attempts=N`, which carries no
  // attribution at all and is emitted by the single shared provider path for
  // every push type and every user on a PRODUCTION box. The relay's own
  // Prometheus counters are reaction-scoped, already exported on
  // `:2112/metrics` (`go-relay-server/main.go:261-266`), and already scraped
  // over ssh by five `docker-ws/` scripts, so grading on their growth across
  // the capture window is both sound and existing repo practice.
  final metrics = parseRelayMetricsWindow(evidenceTexts['relay_metrics'] ?? '');
  if (metrics == null) {
    failures.add(
      r'$.evidence[relay_metrics] is not an ordered baseline/final pair of raw '
      'relay counter scrapes',
    );
  } else if (metrics.isProcessContinuous != true) {
    // Both phases must come from the SAME relay process. The sentinel is a
    // plain counter, exported from registration and monotonic within a process,
    // so a missing or regressed one means the file is truncated or the relay
    // restarted mid-capture — either way no delta below means anything.
    failures.add(
      r'$.evidence[relay_metrics] does not span one continuous relay process',
    );
  } else if (messageScenario) {
    // The message lane has NO wake counter and no per-recipient journal line of
    // any kind: `fanOutPush` contains zero `log.Printf`. Its relay-side
    // observables are `[GROUP_INBOX] Stored message for group` (asserted above,
    // and the window-liveness oracle) plus growth of the shared provider
    // counter. A floor is the strongest honest rule here — the counter is not
    // group-scoped.
    final pushDelta = relayCounterFamilyDelta(metrics, relayPushSentCounter);
    if (pushDelta == null || pushDelta < 1) {
      failures.add(
        r'$.evidence[relay_metrics] shows no provider attempt across the '
        'group-message capture window',
      );
    }
  } else {
    final attempted = metrics.delta(
      relayCounterSeries(relayGroupReactionWakeCounter, const <String, String>{
        'outcome': 'attempted',
      }),
    );
    final routeError = metrics.delta(
      relayCounterSeries(relayGroupReactionWakeCounter, const <String, String>{
        'outcome': 'route_error',
      }),
    );
    final incapableSkipped = metrics.delta(
      relayCounterSeries(relayGroupReactionWakeCounter, const <String, String>{
        'outcome': 'incapable_skipped',
      }),
    );
    if (attempted == null || attempted != expectedRelayWakeAttempts) {
      failures.add(
        r'$.evidence[relay_metrics] wake attempts across the capture window '
        'are not exactly the expected count',
      );
    }
    // A recipient the relay silently declined is the failure mode a bare
    // "at least one dispatch" rule cannot see: `route_error` emits NO journal
    // line at all, and `incapable_skipped` means the recipient advertised no
    // usable route. Both must be zero for the count above to mean what it says.
    if (routeError == null || routeError != 0) {
      failures.add(
        r'$.evidence[relay_metrics] records a wake route error in the capture '
        'window',
      );
    }
    if (incapableSkipped == null || incapableSkipped != 0) {
      failures.add(
        r'$.evidence[relay_metrics] records an incapable-skipped wake in the '
        'capture window',
      );
    }
  }

  final senderEvents = _flowEventNames(senderApp);
  if (messageScenario) {
    if (senderEvents
            .where(
              (event) => event.startsWith('GROUP_SEND_MSG_USE_CASE_SUCCESS'),
            )
            .length <
        2) {
      failures.add(
        r'$.evidence[sender_app] lacks two raw group-message send commits',
      );
    }
  } else {
    if (senderEvents
                .where((event) => event == 'GROUP_REACTION_SEND_QUEUED')
                .length !=
            2 ||
        senderEvents
                .where((event) => event == 'GROUP_REACTION_REMOVE_QUEUED')
                .length !=
            1) {
      failures.add(
        r'$.evidence[sender_app] must contain raw ADD/REMOVE/ADD transitions',
      );
    }
    if (!recipientApp.contains('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK') ||
        !recipientApp.contains('PUSH_ANDROID_DATA_DECRYPT_OK')) {
      failures.add(
        processAliveReaction
            ? r'$.evidence[recipient_app] lacks raw background-connected '
                  'crypto/parity success'
            : r'$.evidence[recipient_app] lacks raw killed-process '
                  'crypto/parity success',
      );
    }
    if (processAliveReaction) {
      _validateBackgroundConnectedObservation(
        recipientApp,
        scenario: requirement.id,
        failures: failures,
      );
    }
    _validateExactDuplicateRedrive(
      senderApp,
      scenario: requirement.id,
      failures: failures,
    );
  }

  _validateSqlCipherRaw(
    sqlCipher,
    requirement: requirement,
    measurements: measurements,
    failures: failures,
  );
  _validateNotificationRaw(
    notificationRecords,
    messageScenario: messageScenario,
    groupName: groupName,
    actorName: actorName,
    appPackage: appPackage,
    failures: failures,
  );
  _validateUiRaw(
    uiAutomation,
    messageScenario: messageScenario,
    groupName: groupName,
    firstMarker: measurements['firstMarker'] as String? ?? '',
    secondMarker: measurements['secondMarker'] as String? ?? '',
    targetMarker: measurements['targetMarker'] as String? ?? '',
    failures: failures,
  );
}

void _validateBackgroundConnectedObservation(
  String text, {
  required String scenario,
  required List<String> failures,
}) {
  final lines = text
      .split('\n')
      .where(
        (line) =>
            line.startsWith(groupReactionBackgroundConnectedObservationPrefix),
      )
      .toList(growable: false);
  if (lines.length != 1) {
    failures.add(
      r'$.evidence[recipient_app] must contain one background-connected '
      'timing observation',
    );
    return;
  }
  final observed = _decodeObject(
    lines.single.substring(
      groupReactionBackgroundConnectedObservationPrefix.length,
    ),
    r'$.evidence[recipient_app].backgroundConnectedObservation',
    failures,
  );
  if (observed == null) return;
  _expectExactKeys(
    observed,
    const <String>{
      'schema',
      'scenario',
      'pidPresentBeforeDelivery',
      'connectivityEvent',
      'connectivityState',
      'connectivityOk',
      'homeAt',
      'reactionAt',
      'notificationAt',
      'minimumHomeToReactDelayMs',
      'homeToReactDelayMs',
      'notificationObservationWindowMs',
      'reactionToNotificationMs',
    },
    r'$.evidence[recipient_app].backgroundConnectedObservation',
    failures,
  );
  final homeAt = DateTime.tryParse('${observed['homeAt']}')?.toUtc();
  final reactionAt = DateTime.tryParse('${observed['reactionAt']}')?.toUtc();
  final notificationAt = DateTime.tryParse(
    '${observed['notificationAt']}',
  )?.toUtc();
  final homeToReaction = observed['homeToReactDelayMs'];
  final reactionToNotification = observed['reactionToNotificationMs'];
  final timestampsOrdered =
      homeAt != null &&
      reactionAt != null &&
      notificationAt != null &&
      !reactionAt.isBefore(homeAt) &&
      !notificationAt.isBefore(reactionAt);
  final derivedHomeToReaction = timestampsOrdered
      ? reactionAt.difference(homeAt).inMilliseconds
      : -1;
  final derivedReactionToNotification = timestampsOrdered
      ? notificationAt.difference(reactionAt).inMilliseconds
      : -1;
  bool closeToDerived(Object? value, int derived) =>
      value is int && (value - derived).abs() <= 1500;
  if (observed['schema'] !=
          'mknoon.plan315.background-connected-observation.v1' ||
      observed['scenario'] != scenario ||
      observed['pidPresentBeforeDelivery'] != true ||
      observed['connectivityEvent'] != 'P2P_RELAY_PRESENCE_SET_RESPONSE' ||
      observed['connectivityState'] != 'background' ||
      observed['connectivityOk'] != true ||
      observed['minimumHomeToReactDelayMs'] !=
          groupReactionBackgroundConnectedHomeToReactDelayMs ||
      observed['notificationObservationWindowMs'] !=
          groupReactionBackgroundConnectedObservationWindowMs ||
      homeToReaction is! int ||
      homeToReaction < groupReactionBackgroundConnectedHomeToReactDelayMs ||
      homeToReaction >
          groupReactionBackgroundConnectedHomeToReactDelayMs + 15000 ||
      reactionToNotification is! int ||
      reactionToNotification < 0 ||
      reactionToNotification >
          groupReactionBackgroundConnectedObservationWindowMs ||
      !timestampsOrdered ||
      !closeToDerived(homeToReaction, derivedHomeToReaction) ||
      !closeToDerived(reactionToNotification, derivedReactionToNotification)) {
    failures.add(
      r'$.evidence[recipient_app] background-connected process, connectivity, '
      'or timing proof mismatched',
    );
  }
}

void _validateExactDuplicateRedrive(
  String senderApp, {
  required String scenario,
  required List<String> failures,
}) {
  final records = senderApp
      .split('\n')
      .where((line) => line.startsWith(_plan257DuplicateRedrivePrefix))
      .toList(growable: false);
  if (records.length != 1) {
    failures.add(
      r'$.evidence[sender_app] must contain one exact stored-ADD redrive '
      'observation',
    );
    return;
  }
  final observation = _decodeObject(
    records.single.substring(_plan257DuplicateRedrivePrefix.length),
    r'$.evidence[sender_app].duplicateRedrive',
    failures,
  );
  if (observation == null) return;
  final identityHashes = <Object?>[
    observation['transitionIdSha256'],
    observation['reactionStateIdSha256'],
    observation['targetMessageIdSha256'],
  ];
  final exactRetryEvents = _flowEventObjects(senderApp)
      .where(
        (event) => event['event'] == 'RETRY_FAILED_GROUP_REACTION_REPLAY_OK',
      )
      .toList(growable: false);
  final retryDetails = exactRetryEvents.length == 1
      ? exactRetryEvents.single['details']
      : null;
  final retryReactionId = retryDetails is Map
      ? retryDetails['reactionId']
      : null;
  final retryPrefixMatches =
      retryReactionId is String &&
      retryReactionId.isNotEmpty &&
      retryReactionId.length <= 8 &&
      retryDetails is Map &&
      retryDetails['action'] == 'add' &&
      sha256.convert(utf8.encode(retryReactionId)).toString() ==
          observation['transitionIdPrefixSha256'];
  if (observation['schema'] !=
          'mknoon.plan257.duplicate-redrive-observation.v1' ||
      observation['scenario'] != scenario ||
      observation['prepared'] != true ||
      observation['notificationExtensionBound'] != true ||
      observation['signedEnvelopePresent'] != true ||
      observation['previousDeliveryStatus'] != 'stored' ||
      identityHashes.any((value) => !_isSha256(value)) ||
      identityHashes.toSet().length != 3 ||
      !_isSha256(observation['transitionIdPrefixSha256']) ||
      !_isSha256(observation['inboxRetryPayloadSha256']) ||
      exactRetryEvents.length != 1 ||
      !retryPrefixMatches) {
    failures.add(
      r'$.evidence[sender_app] does not prove one production redrive of the '
      'exact stored ADD with distinct transition/state/target identities',
    );
  }
}

void _validateIosAuthoritativeEvidence({
  required GroupReactionNotificationScenario requirement,
  required Map<String, Object?> measurements,
  required Map<String, String> evidenceTexts,
  required List<String> failures,
}) {
  final groupName = measurements['groupName'] as String? ?? '';
  final actorName = measurements['actorName'] as String? ?? '';
  final targetMarker = measurements['targetMarker'] as String? ?? '';
  final expectedRelayWakeAttempts =
      measurements['expectedRelayWakeAttempts'] as int? ?? -1;
  final relay = evidenceTexts['relay'] ?? '';
  final provider = evidenceTexts['provider_apns'] ?? '';
  final senderApp = evidenceTexts['sender_app'] ?? '';
  final recipientApp = evidenceTexts['recipient_app'] ?? '';
  final sqlCipher = evidenceTexts['sqlcipher_state'] ?? '';
  final nseLog = evidenceTexts['nse_log'] ?? '';
  final xcuiTest = evidenceTexts['xcuitest'] ?? '';

  final relayCustody = relay
      .split('\n')
      .where((line) => line.contains('[GROUP_INBOX]'))
      .toList(growable: false);
  if (relayCustody.isEmpty ||
      !relayCustody.any(
        (line) => line.contains('[GROUP_INBOX] Stored message for group'),
      ) ||
      relayCustody.any(
        (line) => !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(line),
      )) {
    failures.add(r'$.evidence[relay] is not raw timestamped relay custody');
  }

  final providerLines = provider
      .split('\n')
      .where((line) => line.contains('[PUSH] Notification sent to'))
      .toList(growable: false);
  if (providerLines.length != expectedRelayWakeAttempts ||
      providerLines.any(
        (line) => !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(line),
      )) {
    failures.add(
      r'$.evidence[provider_apns] must contain exactly two raw timestamped '
      'provider accepts after quiescence',
    );
  }

  final senderEvents = _flowEventNames(senderApp);
  if (senderEvents
              .where((event) => event == 'GROUP_REACTION_SEND_QUEUED')
              .length !=
          2 ||
      senderEvents
              .where((event) => event == 'GROUP_REACTION_REMOVE_QUEUED')
              .length !=
          1) {
    failures.add(
      r'$.evidence[sender_app] must contain raw ADD/REMOVE/ADD transitions',
    );
  }

  if (!recipientApp.contains('ios_notification_open_stored_pending') ||
      !recipientApp.contains('IOS_APNS_INITIAL_NOTIFICATION_OPENED') ||
      recipientApp.contains('IOS_APNS_NOTIFICATION_OPEN_ERROR') ||
      recipientApp.contains('NOTIFICATION_TAP_NAV_ERROR') ||
      recipientApp.contains('INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR')) {
    failures.add(
      r'$.evidence[recipient_app] lacks a raw error-free cold notification '
      'open',
    );
  }

  _validateSqlCipherRaw(
    sqlCipher,
    requirement: requirement,
    measurements: measurements,
    failures: failures,
  );

  final nseEvents = _flowEventNames(nseLog);
  if (nseEvents.where((event) => event == 'PUSH_NSE_DECRYPT_OK').length !=
          expectedRelayWakeAttempts ||
      nseEvents.any(
        (event) =>
            event == 'PUSH_NSE_DECRYPT_FAIL' || event == 'PUSH_NSE_TIMEOUT',
      ) ||
      !nseLog.contains('"kind":"group_reaction"')) {
    failures.add(
      r'$.evidence[nse_log] lacks two raw successful group-reaction NSE '
      'resolutions or contains a failure',
    );
  }

  const observationPrefix = 'MKNOON_257_IOS_NOTIFICATION_OBSERVATION ';
  final observations = xcuiTest
      .split('\n')
      .where((line) => line.contains(observationPrefix))
      .toList(growable: false);
  Map<String, Object?>? observation;
  if (observations.length == 1) {
    final encoded = observations.single.substring(
      observations.single.indexOf(observationPrefix) + observationPrefix.length,
    );
    observation = _decodeObject(
      encoded,
      r'$.evidence[xcuitest].notificationObservation',
      failures,
    );
  }
  final expectedBody = '$actorName reacted 👍 to your message';
  if (observation == null ||
      observation['schema'] !=
          'mknoon.plan257.ios-notification-observation.v1' ||
      observation['title'] != groupName ||
      observation['body'] != expectedBody ||
      observation['matchingCardCount'] != 1 ||
      observation['containsNewMessageCopy'] != false) {
    failures.add(
      r'$.evidence[xcuitest] lacks one raw matching Springboard reaction card',
    );
  }
  if (!xcuiTest.contains('testAnnouncementReactionNotificationTap') ||
      !xcuiTest.contains(
        "Test Case '-[RunnerUITests.NotificationTapUITests ",
      ) ||
      !xcuiTest.contains("testAnnouncementReactionNotificationTap]' passed") ||
      !xcuiTest.contains(
        'MKNOON_257_ANNOUNCEMENT_REACTION_TAP '
        'group_rendered=true target_message_visible=true manual_taps=0 '
        'cold_launch=true',
      ) ||
      !xcuiTest.contains(groupName) ||
      !xcuiTest.contains(targetMarker) ||
      xcuiTest.contains('Test Case') &&
          xcuiTest.contains(
            'testAnnouncementReactionNotificationTap] failed',
          )) {
    failures.add(
      r'$.evidence[xcuitest] lacks raw passed selector/card/tap/UI output',
    );
  }
  if (xcuiTest.toLowerCase().contains('new message')) {
    failures.add(r'$.evidence[xcuitest] exposed forbidden New Message copy');
  }
}

List<String> _flowEventNames(String text) {
  return _flowEventObjects(
    text,
  ).map((value) => value['event']).whereType<String>().toList(growable: false);
}

List<Map<String, Object?>> _flowEventObjects(String text) {
  final result = <Map<String, Object?>>[];
  for (final line in text.split('\n')) {
    final marker = line.indexOf('[FLOW]');
    if (marker < 0) continue;
    final jsonStart = line.indexOf('{', marker);
    if (jsonStart < 0) continue;
    try {
      final value = jsonDecode(line.substring(jsonStart));
      if (value is Map && value['event'] is String) {
        result.add(
          value.map<String, Object?>(
            (key, field) => MapEntry(key.toString(), field),
          ),
        );
      }
    } on Object {
      // A malformed raw line contributes no event and is rejected by counts.
    }
  }
  return result;
}

void _validateSqlCipherRaw(
  String text, {
  required GroupReactionNotificationScenario requirement,
  required Map<String, Object?> measurements,
  required List<String> failures,
}) {
  const prefix = 'MKNOON_257_SQLCIPHER_OBSERVATION ';
  final line = text
      .split('\n')
      .where((candidate) => candidate.startsWith(prefix))
      .toList(growable: false);
  if (line.length != 1) {
    failures.add(
      r'$.evidence[sqlcipher_state] must contain one raw observer record',
    );
    return;
  }
  final observed = _decodeObject(
    line.single.substring(prefix.length),
    r'$.evidence[sqlcipher_state]',
    failures,
  );
  if (observed == null) return;
  if (observed['schema'] != 'mknoon.plan257.sqlcipher-observation.v1' ||
      observed['scenario'] != requirement.id ||
      observed['groupName'] != measurements['groupName'] ||
      observed['groupRows'] != 1 ||
      observed['groupType'] != requirement.groupType ||
      observed['unreadCount'] != 0 ||
      observed['reactionMessageRows'] != 0 ||
      observed['markers'] is! List) {
    failures.add(
      r'$.evidence[sqlcipher_state] core SQLCipher observation mismatched',
    );
    return;
  }
  final markers = (observed['markers'] as List)
      .whereType<Map>()
      .map((entry) => Map<String, Object?>.from(entry))
      .toList(growable: false);
  if (requirement.id.endsWith('_message_unread_lifecycle')) {
    final first = markers.where((entry) => entry['marker'] == 'first');
    final second = markers.where((entry) => entry['marker'] == 'second');
    if (first.length != 1 ||
        second.length != 1 ||
        first.single['incoming'] != true ||
        second.single['incoming'] != true ||
        first.single['read'] != true ||
        second.single['read'] != true ||
        observed['reactionRows'] != 0) {
      failures.add(r'$.evidence[sqlcipher_state] message/read rows mismatched');
    }
  } else {
    final target = markers.where((entry) => entry['marker'] == 'target');
    if (target.length != 1 ||
        target.single['incoming'] != false ||
        observed['reactionRows'] != 1 ||
        observed['reactionEmoji'] != '👍' ||
        observed['reactionTargetIdSha256'] != target.single['idSha256']) {
      failures.add(
        r'$.evidence[sqlcipher_state] reaction/target rows mismatched',
      );
    }
  }
}

Map<String, String> _sourceBlocks(String text) {
  final result = <String, String>{};
  String? current;
  var buffer = StringBuffer();
  void commit() {
    final name = current;
    if (name != null) result[name] = buffer.toString();
  }

  for (final line in text.split('\n')) {
    if (line.startsWith('source_file=')) {
      commit();
      current = line.substring('source_file='.length).trim();
      buffer = StringBuffer();
      continue;
    }
    if (current != null) buffer.writeln(line);
  }
  commit();
  return result;
}

void _validateNotificationRaw(
  String text, {
  required bool messageScenario,
  required String groupName,
  required String actorName,
  required String appPackage,
  required List<String> failures,
}) {
  final blocks = _sourceBlocks(text);
  final required = messageScenario
      ? const <String>[
          'notification_message_first.log',
          'notification_message_second.log',
        ]
      : const <String>[
          'notification_reaction_first.log',
          'notification_reaction_replacement.log',
        ];
  final cards = <({int id, String title, String body})>[];
  for (final name in required) {
    final block = blocks[name];
    if (block == null ||
        !block.contains('NotificationRecord(') ||
        !block.contains('pkg=$appPackage')) {
      failures.add(
        r'$.evidence[android_notification_records] lacks raw ' + name,
      );
      continue;
    }
    final contentCards = extractActiveContentNotificationCards(
      block,
      packageName: appPackage,
    );
    if (contentCards.length != 1) {
      failures.add(
        r'$.evidence[android_notification_records] has malformed raw card',
      );
      continue;
    }
    final card = contentCards.single;
    final id = card.id;
    if (id == null || id < 0 || card.title.isEmpty || card.body.isEmpty) {
      failures.add(
        r'$.evidence[android_notification_records] has malformed raw card',
      );
      continue;
    }
    cards.add((id: id, title: card.title, body: card.body));
  }
  if (cards.length == 2 && cards[0].id != cards[1].id) {
    failures.add(
      r'$.evidence[android_notification_records] did not replace one stable '
      'group card',
    );
  }
  if (cards.any(
    (card) =>
        card.title.toLowerCase().contains('new message') ||
        card.body.toLowerCase().contains('new message'),
  )) {
    failures.add(
      r'$.evidence[android_notification_records] exposed New Message copy',
    );
  }
  if (!messageScenario &&
      cards.any(
        (card) =>
            card.title != groupName ||
            card.body !=
                groupReactionNotificationExpectedAndroidReactionBody(actorName),
      )) {
    failures.add(
      r'$.evidence[android_notification_records] reaction title/body mismatch',
    );
  }
}

void _validateUiRaw(
  String text, {
  required bool messageScenario,
  required String groupName,
  required String firstMarker,
  required String secondMarker,
  required String targetMarker,
  required List<String> failures,
}) {
  final blocks = _sourceBlocks(text);
  bool rawBlockContains(String name, List<String> values) {
    final block = blocks[name];
    return block != null &&
        block.contains('<hierarchy') &&
        values.every(block.contains);
  }

  if (messageScenario) {
    final expectations = <String, List<String>>{
      'ui_unread_0.xml': <String>['Open group $groupName'],
      'ui_unread_1.xml': <String>['Open group $groupName, 1 unread message'],
      'ui_unread_1_after_dismiss.xml': <String>[
        'Open group $groupName, 1 unread message',
      ],
      'ui_unread_2.xml': <String>['Open group $groupName, 2 unread messages'],
      'ui_conversation_after_tap.xml': <String>[firstMarker, secondMarker],
      'ui_unread_0_after_tap.xml': <String>['Open group $groupName'],
    };
    for (final entry in expectations.entries) {
      if (!rawBlockContains(entry.key, entry.value)) {
        failures.add(
          r'$.evidence[ui_automation] raw UI snapshot mismatch for ' +
              entry.key,
        );
      }
    }
    for (final name in const <String>[
      'ui_unread_0.xml',
      'ui_unread_0_after_tap.xml',
    ]) {
      if ((blocks[name] ?? '').contains('unread message')) {
        failures.add(
          r'$.evidence[ui_automation] zero state still exposes unread semantics',
        );
      }
    }
  } else {
    for (final entry in <String, List<String>>{
      'ui_reaction_unread_0_before.xml': <String>['Open group $groupName'],
      'ui_reaction_target_after_tap.xml': <String>[targetMarker],
      'ui_reaction_unread_0_after.xml': <String>['Open group $groupName'],
    }.entries) {
      if (!rawBlockContains(entry.key, entry.value)) {
        failures.add(
          r'$.evidence[ui_automation] raw UI snapshot mismatch for ' +
              entry.key,
        );
      }
    }
    if (blocks.values.any((block) => block.contains('unread message'))) {
      failures.add(
        r'$.evidence[ui_automation] reaction created unread semantics',
      );
    }
  }
}

Map<String, Object?>? _asStringMap(
  Object? value,
  String path,
  List<String> failures,
) {
  if (value is! Map) {
    failures.add('$path must be an object');
    return null;
  }
  try {
    return Map<String, Object?>.from(value);
  } on Object {
    failures.add('$path must use string keys');
    return null;
  }
}

Map<String, Object?>? _mapField(
  Map<String, Object?> parent,
  String key,
  String path,
  List<String> failures,
) {
  return _asStringMap(parent[key], '$path.$key', failures);
}

String? _requiredString(
  Map<String, Object?> parent,
  String key,
  String path,
  List<String> failures,
) {
  final value = parent[key];
  if (value is! String || value.trim().isEmpty) {
    failures.add('$path.$key must be a non-empty string');
    return null;
  }
  return value;
}

void _expectValue(
  Map<String, Object?> parent,
  String key,
  Object expected,
  String path,
  List<String> failures,
) {
  if (parent[key] != expected) {
    failures.add('$path.$key must equal $expected');
  }
}

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
  List<String> failures,
) {
  final actual = value.keys.toSet();
  final missing = expected.difference(actual).toList()..sort();
  final extra = actual.difference(expected).toList()..sort();
  if (missing.isNotEmpty) {
    failures.add('$path missing fields: ${missing.join(', ')}');
  }
  if (extra.isNotEmpty) {
    failures.add('$path unexpected fields: ${extra.join(', ')}');
  }
}

void _scanForbidden(String raw, String path, List<String> failures) {
  for (final field in const <String>[
    '"fcmToken":',
    '"apnsToken":',
    '"secretKey":',
    '"ciphertext":',
    '"plaintext":',
    '"senderPeerId":',
    '"recipientPeerId":',
  ]) {
    if (raw.contains(field)) {
      failures.add('$path contains forbidden sensitive field $field');
    }
  }
}
