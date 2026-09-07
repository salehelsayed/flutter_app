import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart'
    hide maybeShowNotification;
import 'package:flutter_app/features/push/application/show_notification_use_case.dart'
    as subject
    show maybeShowNotification;
import '../../../shared/fakes/fake_notification_service.dart';

// Existing preservation cases keep expressing their pre-N04 tracker/lifecycle
// setup through a test-only adapter. The production API has no such arguments;
// TC-371-04 below calls [subject.maybeShowNotification] with explicit snapshot
// evaluations to lock the new authority semantics directly.
Future<NotificationPresentationResult> maybeShowNotification({
  required NotificationService notificationService,
  required ActiveConversationTracker conversationTracker,
  required AppLifecycleState Function() getAppLifecycleState,
  required String contactPeerId,
  String? routePayload,
  required String senderUsername,
  required String messageText,
  bool suppressNotification = false,
  String suppressionReason = 'recovery_replay',
  String? messageId,
  String? notificationEventIdentity,
  ConsumeRecentRemoteNotificationAnnouncement?
  consumeRecentRemoteNotificationAnnouncement,
  MarkRecentRemoteNotificationAnnouncement?
  markRecentRemoteNotificationAnnouncement,
  NotificationToneTracker? toneTracker,
  ResolveDurableNotificationCoordinator? durableNotificationCoordinatorResolver,
  LoadConversationNotificationSnapshot? loadConversationNotificationSnapshot,
  String notificationEventType = 'new_message',
  Duration backgroundDuplicateGuardDelay = const Duration(seconds: 2),
}) => subject.maybeShowNotification(
  notificationService: notificationService,
  appVisibility: _TrackerBackedVisibility(
    tracker: conversationTracker,
    lifecycle: getAppLifecycleState,
  ),
  contactPeerId: contactPeerId,
  routePayload: routePayload,
  senderUsername: senderUsername,
  messageText: messageText,
  suppressNotification: suppressNotification,
  suppressionReason: suppressionReason,
  messageId: messageId,
  notificationEventIdentity: notificationEventIdentity,
  consumeRecentRemoteNotificationAnnouncement:
      consumeRecentRemoteNotificationAnnouncement,
  markRecentRemoteNotificationAnnouncement:
      markRecentRemoteNotificationAnnouncement,
  toneTracker: toneTracker,
  durableNotificationCoordinatorResolver:
      durableNotificationCoordinatorResolver,
  loadConversationNotificationSnapshot: loadConversationNotificationSnapshot,
  notificationEventType: notificationEventType,
  backgroundDuplicateGuardDelay: backgroundDuplicateGuardDelay,
);

final class _TrackerBackedVisibility extends AppVisibilitySuppressionReader {
  _TrackerBackedVisibility({required this.tracker, required this.lifecycle});

  final ActiveConversationTracker tracker;
  final AppLifecycleState Function() lifecycle;

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async {
    final isForegroundActive = lifecycle() == AppLifecycleState.resumed;
    return AppVisibilityEvaluation(
      isForegroundActive: isForegroundActive,
      maySuppress:
          isForegroundActive &&
          identity != null &&
          tracker.isViewing(identity.normalizedValue),
    );
  }
}

final class _SnapshotLikeVisibility extends AppVisibilitySuppressionReader {
  _SnapshotLikeVisibility({
    this.visible,
    this.known = true,
    this.fresh = true,
    this.foregroundActive = true,
  });

  final AppVisibilityConversationIdentity? visible;
  final bool known;
  final bool fresh;
  final bool foregroundActive;
  int evaluations = 0;

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async {
    evaluations += 1;
    if (!known) return AppVisibilityEvaluation.failNotify;
    return AppVisibilityEvaluation(
      isForegroundActive: foregroundActive && fresh,
      maySuppress:
          foregroundActive && fresh && identity != null && identity == visible,
    );
  }
}

void main() {
  late FakeNotificationService notificationService;
  late ActiveConversationTracker tracker;

  setUp(() {
    notificationService = FakeNotificationService();
    tracker = ActiveConversationTracker();
  });

  test('private and unsupported local preview bodies are always generic', () {
    final variants = [
      PrivateMediaPolicy.fromJson(const {'version': 1, 'mode': 'protected'}),
      const PrivateMediaPolicy.unsupported(sourceVersion: 9),
    ];

    for (final policy in variants) {
      expect(
        notificationBodyForMessage(
          'caption-canary',
          const [],
          privateMediaPolicy: policy,
        ),
        'Private media',
      );
    }
  });

  test('private local preview uses generated en/de/ar copy', () {
    final policy = PrivateMediaPolicy.fromJson(const {
      'version': 1,
      'mode': 'protected',
    });
    for (final testCase in const [
      (Locale('en'), 'Private media'),
      (Locale('de'), 'Private Medien'),
      (Locale('ar'), 'وسائط خاصة'),
    ]) {
      expect(
        notificationBodyForMessage(
          'caption-canary',
          const [],
          privateMediaPolicy: policy,
          locale: testCase.$1,
        ),
        testCase.$2,
        reason: testCase.$1.languageCode,
      );
    }
  });

  group('maybeShowNotification', () {
    test(
      'TC-371-04 one fresh visibility decision gates direct and group presentation without minting outcome',
      () async {
        final directA = AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.direct,
          value: 'peer-a',
        )!;
        final groupA = AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.group,
          value: 'group:a',
        )!;
        final cases =
            <
              ({
                String label,
                String contactPeerId,
                _SnapshotLikeVisibility visibility,
                bool suppressed,
              })
            >[
              (
                label: 'fresh direct exact A',
                contactPeerId: 'peer-a',
                visibility: _SnapshotLikeVisibility(visible: directA),
                suppressed: true,
              ),
              (
                label: 'fresh group exact A',
                contactPeerId: 'group:a',
                visibility: _SnapshotLikeVisibility(visible: groupA),
                suppressed: true,
              ),
              (
                label: 'fresh direct B',
                contactPeerId: 'peer-b',
                visibility: _SnapshotLikeVisibility(visible: directA),
                suppressed: false,
              ),
              (
                label: 'stale exact A',
                contactPeerId: 'peer-a',
                visibility: _SnapshotLikeVisibility(
                  visible: directA,
                  fresh: false,
                ),
                suppressed: false,
              ),
              (
                label: 'unknown snapshot',
                contactPeerId: 'peer-a',
                visibility: _SnapshotLikeVisibility(known: false),
                suppressed: false,
              ),
              (
                label: 'inactive exact A',
                contactPeerId: 'peer-a',
                visibility: _SnapshotLikeVisibility(
                  visible: directA,
                  foregroundActive: false,
                ),
                suppressed: false,
              ),
              (
                label: 'non-chat identity',
                contactPeerId: ' ',
                visibility: _SnapshotLikeVisibility(visible: directA),
                suppressed: false,
              ),
            ];

        for (final testCase in cases) {
          final service = FakeNotificationService();
          final result = await subject.maybeShowNotification(
            notificationService: service,
            appVisibility: testCase.visibility,
            contactPeerId: testCase.contactPeerId,
            senderUsername: 'Alice',
            messageText: 'Hello',
            backgroundDuplicateGuardDelay: Duration.zero,
          );

          expect(
            testCase.visibility.evaluations,
            testCase.suppressed ? 1 : 2,
            reason:
                '${testCase.label}: eligible presentation must re-evaluate '
                'once at the Plan 393 native-entry boundary',
          );
          if (testCase.suppressed) {
            expect(
              result,
              NotificationPresentationResult.terminalWithoutOutcome,
              reason: testCase.label,
            );
            expect(result.carriesApprovedOutcome, isFalse);
            expect(service.shown, isEmpty, reason: testCase.label);
          } else {
            expect(
              result,
              NotificationPresentationResult.osPosted,
              reason: testCase.label,
            );
            expect(service.shown, hasLength(1), reason: testCase.label);
          }
        }
      },
    );

    test(
      'TC-372-03b early visibility is preparation only and final gate owns the result',
      () async {
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.direct,
          value: 'peer-final-visibility',
        )!;
        final cases = <({bool earlyVisible, bool finalVisible})>[
          (earlyVisible: true, finalVisible: false),
          (earlyVisible: false, finalVisible: true),
        ];

        for (final testCase in cases) {
          final ownerDirectory = await Directory.systemTemp.createTemp(
            'final-barrier-owner-order-',
          );
          addTearDown(() => ownerDirectory.delete(recursive: true));
          final ownerCoordinator = DurableNotificationToneLease(
            directory: ownerDirectory,
            pendingClaimWait: Duration.zero,
            pendingToneReservationWait: Duration.zero,
          );
          final log = <String>[];
          var observedArmedOwners = false;
          final service = _DurableBoundaryNotificationService(
            log: log,
            beforeAuthorize: () async {
              final publishingFiles = ownerDirectory
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where(
                    (file) => file.readAsStringSync().contains(
                      '"state":"publishing"',
                    ),
                  )
                  .length;
              observedArmedOwners = publishingFiles >= 2;
            },
          );
          final visibility = _SequencedVisibility(<AppVisibilityEvaluation>[
            testCase.earlyVisible
                ? _exactForegroundEvaluation(maySuppress: true, revision: 1)
                : _exactBackgroundEvaluation(revision: 1),
            testCase.finalVisible
                ? _exactForegroundEvaluation(maySuppress: true, revision: 2)
                : _exactBackgroundEvaluation(revision: 2),
          ]);
          final context = DurableLocalNotificationEffectContext(
            currentOpaqueBinding: 'v1:${'a' * 64}',
            eventCorrelation: testCase.earlyVisible ? 'b' * 64 : 'c' * 64,
            conversationDigest: identity.digest,
            producerKind: LocalNotificationProducerKind.directMessage,
            sourceCustody: LocalNotificationSourceCustody.sqlReady,
            presentationOwner: LocalNotificationPresentationOwner.mainApp,
            readFinalCanonicalDisposition: () async =>
                DurableLocalNotificationCanonicalDisposition.eligible,
            onEffectTerminal: (receipt) async {
              log.add('observer:${receipt.presentationState.wireName}');
            },
            terminalObserverCompletesSqlHandoff: true,
          );
          var legacyRemoteConsumes = 0;

          final result = await subject.maybeShowNotification(
            notificationService: service,
            appVisibility: visibility,
            contactPeerId: 'peer-final-visibility',
            senderUsername: 'Alice',
            messageText: 'Hello',
            notificationEventIdentity: context.eventCorrelation,
            durableEffectContext: context,
            durableNotificationCoordinatorResolver: () async =>
                ownerCoordinator,
            consumeRecentRemoteNotificationAnnouncement:
                ({required String payload, String? messageId}) async {
                  legacyRemoteConsumes += 1;
                  return true;
                },
            backgroundDuplicateGuardDelay: Duration.zero,
          );

          expect(visibility.evaluations, 2);
          expect(
            observedArmedOwners,
            isTrue,
            reason:
                'event and tone owners must arm before the final visibility read',
          );
          expect(legacyRemoteConsumes, 1);
          expect(
            result,
            testCase.finalVisible
                ? NotificationPresentationResult.inChat
                : NotificationPresentationResult.osPosted,
          );
          expect(service.nativeCalls, testCase.finalVisible ? 0 : 1);
          expect(
            log.sublist(log.length - 3),
            <String>[
              'service_return',
              'observer:${testCase.finalVisible ? 'IN_CHAT' : 'OS_POSTED'}',
              'reconcile',
            ],
            reason:
                'reconciliation runs only after the out-of-lock SQL observer',
          );
        }
      },
    );

    test(
      'iOS group remote adoption retains proof until durable SQL handoff succeeds',
      () async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(
          () => debugDefaultTargetPlatformOverride = previousPlatform,
        );
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.group,
          value: 'group:remote-adoption-handoff',
        )!;
        final log = <String>[];
        final service = _DurableBoundaryNotificationService(log: log);
        final context = DurableLocalNotificationEffectContext(
          currentOpaqueBinding: 'v1:${'a' * 64}',
          eventCorrelation: 'b' * 64,
          conversationDigest: identity.digest,
          producerKind: LocalNotificationProducerKind.groupMessage,
          sourceCustody: LocalNotificationSourceCustody.sqlReady,
          presentationOwner: LocalNotificationPresentationOwner.mainApp,
          readFinalCanonicalDisposition: () async =>
              DurableLocalNotificationCanonicalDisposition.eligible,
          onEffectTerminal: (_) async => throw StateError('SQL unavailable'),
          terminalObserverCompletesSqlHandoff: true,
        );
        var probes = 0;
        var legacyConsumes = 0;
        var exactProofConsumes = 0;

        final result = await subject.maybeShowNotification(
          notificationService: service,
          appVisibility: _SequencedVisibility(<AppVisibilityEvaluation>[
            _exactForegroundEvaluation(maySuppress: false, revision: 1),
          ]),
          contactPeerId: 'group:remote-adoption-handoff',
          routePayload: 'group:remote-adoption-handoff|message:remote-message',
          senderUsername: 'Group',
          messageText: 'Alice: hello',
          messageId: 'remote-message',
          notificationEventIdentity: context.eventCorrelation,
          notificationEventType: 'group_message',
          durableEffectContext: context,
          probeRecentRemoteNotificationAnnouncement:
              ({required String payload, String? messageId}) async {
                probes += 1;
                return true;
              },
          consumeRecentRemoteNotificationAnnouncement:
              ({required String payload, String? messageId}) async {
                legacyConsumes += 1;
                return true;
              },
          consumeEstablishedRemotePresentationProof: () async {
            exactProofConsumes += 1;
            return true;
          },
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(result, NotificationPresentationResult.osPosted);
        expect(service.nativeCalls, 0);
        expect(probes, 1);
        expect(
          exactProofConsumes,
          0,
          reason: 'failed SQL handoff must leave exact remote proof retryable',
        );
        expect(legacyConsumes, 0);
      },
    );

    test(
      'iOS durable direct remote presentation skips native publication and clears proof after SQL handoff',
      () async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(
          () => debugDefaultTargetPlatformOverride = previousPlatform,
        );
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.direct,
          value: 'peer-remote-adoption-handoff',
        )!;
        final log = <String>[];
        final service = _DurableBoundaryNotificationService(log: log);
        final visibility = _SequencedVisibility(<AppVisibilityEvaluation>[
          _exactForegroundEvaluation(maySuppress: false, revision: 1),
          _exactForegroundEvaluation(maySuppress: false, revision: 2),
        ]);
        final context = DurableLocalNotificationEffectContext(
          currentOpaqueBinding: 'v1:${'a' * 64}',
          eventCorrelation: 'c' * 64,
          conversationDigest: identity.digest,
          producerKind: LocalNotificationProducerKind.directMessage,
          sourceCustody: LocalNotificationSourceCustody.sqlReady,
          presentationOwner: LocalNotificationPresentationOwner.mainApp,
          readFinalCanonicalDisposition: () async =>
              DurableLocalNotificationCanonicalDisposition.eligible,
          onEffectTerminal: (_) async => log.add('sql_handoff'),
          terminalObserverCompletesSqlHandoff: true,
        );
        var probes = 0;
        var legacyConsumes = 0;
        var exactProofConsumes = 0;

        final result = await subject.maybeShowNotification(
          notificationService: service,
          appVisibility: visibility,
          contactPeerId: 'peer-remote-adoption-handoff',
          routePayload: 'peer-remote-adoption-handoff',
          senderUsername: 'Alice',
          messageText: 'hello',
          messageId: 'remote-direct-message',
          notificationEventIdentity: context.eventCorrelation,
          durableEffectContext: context,
          probeRecentRemoteNotificationAnnouncement:
              ({required String payload, String? messageId}) async {
                probes += 1;
                log.add('probe');
                expect(payload, 'peer-remote-adoption-handoff');
                expect(messageId, 'remote-direct-message');
                return true;
              },
          consumeRecentRemoteNotificationAnnouncement:
              ({required String payload, String? messageId}) async {
                legacyConsumes += 1;
                log.add('legacy_consume');
                expect(payload, 'peer-remote-adoption-handoff');
                expect(messageId, 'remote-direct-message');
                return true;
              },
          consumeEstablishedRemotePresentationProof: () async {
            exactProofConsumes += 1;
            log.add('exact_consume');
            return true;
          },
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(result, NotificationPresentationResult.osPosted);
        expect(service.nativeCalls, 0);
        expect(visibility.evaluations, 1);
        expect(probes, 1);
        expect(legacyConsumes, 0);
        expect(exactProofConsumes, 1);
        expect(log, <String>[
          'probe',
          'service_return',
          'sql_handoff',
          'reconcile',
          'exact_consume',
        ]);
      },
    );

    test(
      'iOS durable direct reaction preserves exact remote proof across failed SQL handoff',
      () async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(
          () => debugDefaultTargetPlatformOverride = previousPlatform,
        );
        const peerId = 'peer-reaction-remote-adoption';
        const reactionId = 'reaction-already-shown';
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.direct,
          value: peerId,
        )!;
        final service = _DurableBoundaryNotificationService(log: <String>[]);
        final visibility = _SequencedVisibility(<AppVisibilityEvaluation>[
          _exactForegroundEvaluation(maySuppress: false, revision: 1),
          _exactForegroundEvaluation(maySuppress: false, revision: 2),
          _exactForegroundEvaluation(maySuppress: false, revision: 3),
          _exactForegroundEvaluation(maySuppress: false, revision: 4),
        ]);
        var sqlAvailable = false;
        var proofPresent = true;
        var probes = 0;
        var consumes = 0;
        var legacyConsumes = 0;
        final context = DurableLocalNotificationEffectContext(
          currentOpaqueBinding: 'v1:${'a' * 64}',
          eventCorrelation: 'e' * 64,
          conversationDigest: identity.digest,
          producerKind: LocalNotificationProducerKind.directReaction,
          sourceCustody: LocalNotificationSourceCustody.sqlReady,
          presentationOwner: LocalNotificationPresentationOwner.mainApp,
          readFinalCanonicalDisposition: () async =>
              DurableLocalNotificationCanonicalDisposition.eligible,
          onEffectTerminal: (_) async {
            if (!sqlAvailable) throw StateError('SQL handoff interrupted');
          },
          terminalObserverCompletesSqlHandoff: true,
        );

        Future<void> retry() async {
          await subject.maybeShowNotification(
            notificationService: service,
            appVisibility: visibility,
            contactPeerId: peerId,
            routePayload: '$peerId|message:authored-target',
            senderUsername: 'Alice',
            messageText: 'Reacted to your message',
            messageId: reactionId,
            notificationEventIdentity: context.eventCorrelation,
            notificationEventType: 'message_reaction',
            durableEffectContext: context,
            probeRecentRemoteNotificationAnnouncement:
                ({required String payload, String? messageId}) async {
                  expect(payload, '$peerId|message:authored-target');
                  expect(messageId, reactionId);
                  probes += 1;
                  return proofPresent;
                },
            consumeRecentRemoteNotificationAnnouncement:
                ({required String payload, String? messageId}) async {
                  legacyConsumes += 1;
                  return proofPresent;
                },
            consumeEstablishedRemotePresentationProof: () async {
              expect(sqlAvailable, isTrue);
              consumes += 1;
              proofPresent = false;
              return true;
            },
            backgroundDuplicateGuardDelay: Duration.zero,
          );
        }

        await retry();
        expect(service.nativeCalls, 0);
        expect(proofPresent, isTrue);
        expect(consumes, 0);
        sqlAvailable = true;
        await retry();
        expect(service.nativeCalls, 0);
        expect(probes, 2);
        expect(legacyConsumes, 0);
        expect(consumes, 1);
        expect(proofPresent, isFalse);
      },
    );

    test(
      'iOS durable remote adoption requires matching event and producer kinds',
      () async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(
          () => debugDefaultTargetPlatformOverride = previousPlatform,
        );
        final cases =
            <
              ({
                String name,
                String contactPeerId,
                String eventType,
                LocalNotificationProducerKind producerKind,
                String? messageId,
                bool proofFound,
                int expectedProbes,
              })
            >[
              (
                name: 'reaction with message producer',
                contactPeerId: 'peer-remote-adoption-scope',
                eventType: 'message_reaction',
                producerKind: LocalNotificationProducerKind.directMessage,
                messageId: 'reaction-1',
                proofFound: true,
                expectedProbes: 0,
              ),
              (
                name: 'reaction proof miss',
                contactPeerId: 'peer-remote-adoption-scope',
                eventType: 'message_reaction',
                producerKind: LocalNotificationProducerKind.directReaction,
                messageId: 'reaction-2',
                proofFound: false,
                expectedProbes: 1,
              ),
              (
                name: 'group reaction remains excluded',
                contactPeerId: 'group:remote-adoption-scope',
                eventType: 'message_reaction',
                producerKind: LocalNotificationProducerKind.groupReaction,
                messageId: 'group-reaction-1',
                proofFound: true,
                expectedProbes: 0,
              ),
              (
                name: 'wrong producer',
                contactPeerId: 'peer-remote-adoption-scope',
                eventType: 'new_message',
                producerKind: LocalNotificationProducerKind.groupMessage,
                messageId: 'message-1',
                proofFound: true,
                expectedProbes: 0,
              ),
              (
                name: 'missing message id',
                contactPeerId: 'peer-remote-adoption-scope',
                eventType: 'new_message',
                producerKind: LocalNotificationProducerKind.directMessage,
                messageId: null,
                proofFound: true,
                expectedProbes: 0,
              ),
              (
                name: 'exact proof miss',
                contactPeerId: 'peer-remote-adoption-scope',
                eventType: 'new_message',
                producerKind: LocalNotificationProducerKind.directMessage,
                messageId: 'message-2',
                proofFound: false,
                expectedProbes: 1,
              ),
              (
                name: 'group reaction producer',
                contactPeerId: 'group:remote-adoption-scope',
                eventType: 'group_message',
                producerKind: LocalNotificationProducerKind.groupReaction,
                messageId: 'group-message-1',
                proofFound: true,
                expectedProbes: 0,
              ),
            ];

        for (final testCase in cases) {
          final identity = AppVisibilityConversationIdentity.tryParse(
            lane: testCase.contactPeerId.startsWith('group:')
                ? AppVisibilityConversationLane.group
                : AppVisibilityConversationLane.direct,
            value: testCase.contactPeerId,
          )!;
          final log = <String>[];
          final service = _DurableBoundaryNotificationService(log: log);
          final visibility = _SequencedVisibility(<AppVisibilityEvaluation>[
            _exactForegroundEvaluation(maySuppress: false, revision: 1),
            _exactForegroundEvaluation(maySuppress: false, revision: 2),
          ]);
          final context = DurableLocalNotificationEffectContext(
            currentOpaqueBinding: 'v1:${'a' * 64}',
            eventCorrelation: 'd' * 64,
            conversationDigest: identity.digest,
            producerKind: testCase.producerKind,
            sourceCustody: LocalNotificationSourceCustody.sqlReady,
            presentationOwner: LocalNotificationPresentationOwner.mainApp,
            readFinalCanonicalDisposition: () async =>
                DurableLocalNotificationCanonicalDisposition.eligible,
            onEffectTerminal: (_) async {},
            terminalObserverCompletesSqlHandoff: true,
          );
          var probes = 0;
          var exactProofConsumes = 0;

          final result = await subject.maybeShowNotification(
            notificationService: service,
            appVisibility: visibility,
            contactPeerId: testCase.contactPeerId,
            routePayload: testCase.contactPeerId,
            senderUsername: 'Alice',
            messageText: testCase.name,
            messageId: testCase.messageId,
            notificationEventIdentity: context.eventCorrelation,
            notificationEventType: testCase.eventType,
            durableEffectContext: context,
            probeRecentRemoteNotificationAnnouncement:
                ({required String payload, String? messageId}) async {
                  probes += 1;
                  return testCase.proofFound;
                },
            consumeEstablishedRemotePresentationProof: () async {
              exactProofConsumes += 1;
              return true;
            },
            backgroundDuplicateGuardDelay: Duration.zero,
          );

          expect(
            result,
            NotificationPresentationResult.osPosted,
            reason: testCase.name,
          );
          expect(service.nativeCalls, 1, reason: testCase.name);
          expect(probes, testCase.expectedProbes, reason: testCase.name);
          expect(exactProofConsumes, 0, reason: testCase.name);
        }
      },
    );

    test('TC-393-03 compatibility final visibility barrier', () async {
      final visibility = _SequencedVisibility(<AppVisibilityEvaluation>[
        _exactBackgroundEvaluation(revision: 1),
        _exactForegroundEvaluation(maySuppress: true, revision: 2),
      ]);
      final service = _NativeBoundaryNotificationService();

      final resultFuture = subject.maybeShowNotification(
        notificationService: service,
        appVisibility: visibility,
        contactPeerId: 'peer-final-compatibility',
        senderUsername: 'Alice',
        messageText: 'Racing visibility',
        messageId: 'message-final-compatibility',
        backgroundDuplicateGuardDelay: Duration.zero,
      );
      await service.nativeBoundaryEntered.future;
      service.releaseNativeBoundary.complete();
      final result = await resultFuture;

      expect(visibility.evaluations, 2);
      expect(service.nativeCalls, 0);
      expect(service.shown, isEmpty);
      expect(
        result,
        NotificationPresentationResult.contendedRetryable,
        reason: 'a pre-native visibility denial releases compatibility owners',
      );
    });

    test(
      'terminal OS replay after tone horizon releases provisional owners without native bookkeeping',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'terminal-os-replay-owners-',
        );
        addTearDown(() => directory.delete(recursive: true));
        var now = DateTime.utc(2026, 8, 16, 12);
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          now: () => now,
          pendingClaimWait: Duration.zero,
          pendingToneReservationWait: Duration.zero,
        );
        final priorTone = await coordinator.reserveTone('peer-terminal-replay');
        expect(priorTone, isNotNull);
        expect(await priorTone!.commit(), isTrue);
        now = now.add(const Duration(seconds: 61));

        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.direct,
          value: 'peer-terminal-replay',
        )!;
        final context = DurableLocalNotificationEffectContext(
          currentOpaqueBinding: 'v1:${'d' * 64}',
          eventCorrelation: 'e' * 64,
          conversationDigest: identity.digest,
          producerKind: LocalNotificationProducerKind.directMessage,
          sourceCustody: LocalNotificationSourceCustody.sqlReady,
          presentationOwner: LocalNotificationPresentationOwner.mainApp,
          readFinalCanonicalDisposition: () async =>
              DurableLocalNotificationCanonicalDisposition.eligible,
          onEffectTerminal: (_) async {},
        );
        final service = _DurableBoundaryNotificationService(
          log: <String>[],
          terminalReplay: true,
        );
        var recentMarks = 0;

        final result = await subject.maybeShowNotification(
          notificationService: service,
          appVisibility: _SequencedVisibility(<AppVisibilityEvaluation>[
            _exactBackgroundEvaluation(revision: 1),
          ]),
          contactPeerId: 'peer-terminal-replay',
          senderUsername: 'Alice',
          messageText: 'Hello',
          messageId: 'message-terminal-replay',
          notificationEventIdentity: context.eventCorrelation,
          durableNotificationCoordinatorResolver: () async => coordinator,
          durableEffectContext: context,
          markRecentRemoteNotificationAnnouncement:
              ({required String payload, String? messageId}) async {
                recentMarks += 1;
              },
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(result, NotificationPresentationResult.osPosted);
        expect(service.nativeCalls, 0);
        expect(recentMarks, 0);
        expect(_pendingToneFiles(directory), isEmpty);
        expect(
          await coordinator.reserveTone('peer-terminal-replay'),
          isNotNull,
          reason: 'the replay-only provisional tone owner must be released',
        );
      },
    );

    test('group message and reaction tag shared-card ownership', () async {
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
        contactPeerId: 'group:message-kind',
        senderUsername: 'Team',
        messageText: 'Alice: hello',
        notificationEventType: 'group_message',
      );
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
        contactPeerId: 'group:reaction-kind',
        senderUsername: 'Team',
        messageText: 'Alice reacted to your message',
        notificationEventType: 'message_reaction',
      );

      expect(
        notificationService.shown.map((entry) => entry.contentKind),
        <ConversationNotificationContentKind>[
          ConversationNotificationContentKind.message,
          ConversationNotificationContentKind.reaction,
        ],
      );
    });

    test('direct reaction publishes exact managed-card metadata', () async {
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
        contactPeerId: 'peer-direct-reaction',
        senderUsername: 'Alice',
        messageText: 'Alice reacted to your message',
        notificationEventType: 'message_reaction',
        notificationEventIdentity: boundedReactionEventIdentity(
          'reaction-direct',
        ),
      );

      expect(
        notificationService.shown.single.contentKind,
        ConversationNotificationContentKind.reaction,
      );
      expect(
        notificationService.shown.single.contentEventIdentity,
        boundedReactionEventIdentity('reaction-direct'),
      );
    });

    test(
      'typed claim disposition distinguishes pending from committed',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'typed-notification-disposition-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final owner = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
        );
        final claim = await owner.claimMessageEvent(
          type: 'group_message',
          eventIdentity: 'typed-group-event',
        );
        expect(claim, isNotNull);

        Future<NotificationPresentationResult> attempt() {
          return maybeShowNotification(
            notificationService: notificationService,
            conversationTracker: tracker,
            getAppLifecycleState: () => AppLifecycleState.paused,
            contactPeerId: 'group:typed-disposition',
            senderUsername: 'Team',
            messageText: 'Message',
            messageId: 'typed-group-event',
            notificationEventType: 'group_message',
            durableNotificationCoordinatorResolver: () async =>
                DurableNotificationToneLease(
                  directory: directory,
                  pendingClaimWait: Duration.zero,
                ),
          );
        }

        expect(
          await attempt(),
          NotificationPresentationResult.contendedRetryable,
        );
        expect(notificationService.shown, isEmpty);

        expect(await claim!.commit(), isTrue);
        expect(
          await attempt(),
          NotificationPresentationResult.terminalSuppressed,
        );
        expect(notificationService.shown, isEmpty);
      },
    );

    test('TC-369-03 only an approved completed effect carries an outcome', () async {
      expect(
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:shown-result',
          senderUsername: 'Team',
          messageText: 'Shown',
        ),
        NotificationPresentationResult.osPosted,
      );
      expect(
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:suppressed-result',
          senderUsername: 'Team',
          messageText: 'Suppressed',
          suppressNotification: true,
        ),
        NotificationPresentationResult.terminalWithoutOutcome,
      );
      tracker.setActive('group:visible-result');
      expect(
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'group:visible-result',
          senderUsername: 'Team',
          messageText: 'Visible',
        ),
        NotificationPresentationResult.terminalWithoutOutcome,
      );
      tracker.clear();
      expect(
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:remote-result',
          senderUsername: 'Team',
          messageText: 'Remote',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async => true,
          backgroundDuplicateGuardDelay: Duration.zero,
        ),
        NotificationPresentationResult.terminalWithoutOutcome,
      );
      expect(
        NotificationPresentationResult.inChat.carriesApprovedOutcome,
        isTrue,
      );
      expect(
        NotificationPresentationResult.suppressedPolicy.carriesApprovedOutcome,
        isTrue,
      );
      expect(
        NotificationPresentationResult
            .terminalWithoutOutcome
            .carriesApprovedOutcome,
        isFalse,
      );

      final ambiguousService = _HookedNotificationService((_) async {
        throw StateError('native result is ambiguous');
      });
      await expectLater(
        maybeShowNotification(
          notificationService: ambiguousService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:ambiguous-result',
          senderUsername: 'Team',
          messageText: 'Ambiguous',
        ),
        throwsA(isA<StateError>()),
      );

      final directory = await Directory.systemTemp.createTemp(
        'tc369-post-show-bookkeeping-failure-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final postShowService = FakeNotificationService();
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        pendingClaimWait: Duration.zero,
        pendingToneReservationWait: Duration.zero,
      );
      final claimFile = File(
        '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/'
        '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'tc369-post-show-message')}',
      );

      Future<NotificationPresentationResult> showAfterMarkerFault() =>
          maybeShowNotification(
            notificationService: postShowService,
            conversationTracker: tracker,
            getAppLifecycleState: () => AppLifecycleState.paused,
            contactPeerId: 'peer-tc369-post-show',
            senderUsername: 'Alice',
            messageText: 'Already displayed',
            messageId: 'tc369-post-show-message',
            durableNotificationCoordinatorResolver: () async => coordinator,
            markRecentRemoteNotificationAnnouncement:
                ({required payload, String? messageId}) async {
                  throw StateError('synthetic post-show marker failure');
                },
          );

      expect(
        await showAfterMarkerFault(),
        NotificationPresentationResult.osPosted,
        reason:
            'a bookkeeping error after the native callback cannot erase the completed OS effect',
      );
      expect(postShowService.shown, hasLength(1));
      expect(claimFile.readAsStringSync(), contains('"state":"committed"'));
      expect(_pendingToneFiles(directory), isEmpty);
      expect(
        await showAfterMarkerFault(),
        NotificationPresentationResult.terminalWithoutOutcome,
      );
      expect(postShowService.shown, hasLength(1));
    });

    test(
      'concurrent live producers claim one message and make one tone decision',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'live-notification-claim-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final showEntered = Completer<void>();
        final releaseShow = Completer<void>();
        final start = Completer<void>();
        var toneWrites = 0;
        final service = _HookedNotificationService((attempt) async {
          if (!showEntered.isCompleted) showEntered.complete();
          await releaseShow.future;
        });
        DurableNotificationToneLease coordinator() =>
            DurableNotificationToneLease(
              directory: directory,
              pendingClaimWait: const Duration(milliseconds: 100),
              beforeToneWrite: () async => toneWrites++,
            );

        Future<void> produce(DurableNotificationToneLease owner) async {
          await start.future;
          await maybeShowNotification(
            notificationService: service,
            conversationTracker: tracker,
            getAppLifecycleState: () => AppLifecycleState.paused,
            contactPeerId: 'peer-race',
            senderUsername: 'Alice',
            messageText: 'Same logical message',
            messageId: 'message-race-1',
            durableNotificationCoordinatorResolver: () async => owner,
          );
        }

        final producers = [produce(coordinator()), produce(coordinator())];
        start.complete();
        await showEntered.future;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        releaseShow.complete();
        await Future.wait(producers);

        expect(service.attempts, 1);
        expect(service.shown, hasLength(1));
        expect(service.shown.single.silent, isFalse);
        expect(toneWrites, 1);
      },
    );

    test(
      'concurrent group or announcement reactions share one exact owner',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'live-group-notification-claim-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final showEntered = Completer<void>();
        final releaseShow = Completer<void>();
        final start = Completer<void>();
        var toneWrites = 0;
        final service = _HookedNotificationService((_) async {
          if (!showEntered.isCompleted) showEntered.complete();
          await releaseShow.future;
        });
        DurableNotificationToneLease coordinator() =>
            DurableNotificationToneLease(
              directory: directory,
              pendingClaimWait: const Duration(milliseconds: 100),
              beforeToneWrite: () async => toneWrites++,
            );

        Future<void> produce(DurableNotificationToneLease owner) async {
          await start.future;
          await maybeShowNotification(
            notificationService: service,
            conversationTracker: tracker,
            getAppLifecycleState: () => AppLifecycleState.paused,
            contactPeerId: 'group:announcement-race',
            routePayload: 'group:announcement-race|message:reaction-target-1',
            senderUsername: 'Announcements',
            messageText: 'Alice reacted 👍 to your announcement',
            messageId: 'announcement-reaction-event-1',
            notificationEventIdentity: boundedReactionEventIdentity(
              'announcement-reaction-event-1',
            ),
            notificationEventType: 'message_reaction',
            durableNotificationCoordinatorResolver: () async => owner,
          );
        }

        final producers = [produce(coordinator()), produce(coordinator())];
        start.complete();
        await showEntered.future;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        releaseShow.complete();
        await Future.wait(producers);

        expect(service.attempts, 1);
        expect(service.shown, hasLength(1));
        expect(toneWrites, 1);
        expect(
          File(
            '${directory.path}/NotificationServiceDedupe/'
            '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity('announcement-reaction-event-1'))}',
          ).existsSync(),
          isTrue,
        );
      },
    );

    test(
      'reaction native-attempt error preserves fail-closed exact ownership',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'live-notification-release-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final firstShowEntered = Completer<void>();
        final failFirstShow = Completer<void>();
        final contenderWaitingToRetry = Completer<void>();
        final allowContenderRetry = Completer<void>();
        final service = _HookedNotificationService((attempt) async {
          if (attempt != 1) return;
          firstShowEntered.complete();
          await failFirstShow.future;
          throw StateError('synthetic notification show failure');
        });
        var coordinatorIndex = 0;
        DurableNotificationToneLease coordinator() {
          final isContender = coordinatorIndex++ == 1;
          return DurableNotificationToneLease(
            directory: directory,
            pendingClaimWait: const Duration(milliseconds: 100),
            pendingClaimDelay: isContender
                ? (_) {
                    contenderWaitingToRetry.complete();
                    return allowContenderRetry.future;
                  }
                : null,
          );
        }

        Future<NotificationPresentationResult> produce(
          DurableNotificationToneLease owner,
        ) {
          return maybeShowNotification(
            notificationService: service,
            conversationTracker: tracker,
            getAppLifecycleState: () => AppLifecycleState.paused,
            contactPeerId: 'peer-retry',
            senderUsername: 'Alice',
            messageText: 'Retry me',
            messageId: 'reaction-retry-1',
            notificationEventIdentity: boundedReactionEventIdentity(
              'reaction-retry-1',
            ),
            notificationEventType: 'message_reaction',
            durableNotificationCoordinatorResolver: () async => owner,
          );
        }

        final failedOwner = produce(coordinator());
        await firstShowEntered.future;
        final contender = produce(coordinator());
        await contenderWaitingToRetry.future;
        failFirstShow.complete();

        await expectLater(
          failedOwner,
          throwsA(isA<DurableNotificationPublicationAttemptedException>()),
        );
        allowContenderRetry.complete();
        expect(
          await contender,
          NotificationPresentationResult.contendedRetryable,
        );
        expect(service.attempts, 1);
        expect(service.shown, isEmpty);
        final claimFile = File(
          '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity('reaction-retry-1'))}',
        );
        expect(
          claimFile.readAsStringSync(),
          contains('"state":"publishing"'),
          reason: 'a native callback error cannot prove the card was not shown',
        );
        expect(
          _onlyPendingToneFile(directory).readAsStringSync(),
          contains('"state":"publishing"'),
        );
      },
    );

    test(
      'non-Android delayed show preserves pending claim and tone until display success',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'live-notification-delayed-show-',
        );
        addTearDown(() => directory.delete(recursive: true));
        var now = DateTime.utc(2026, 7, 12, 10);
        final showEntered = Completer<void>();
        final releaseShow = Completer<void>();
        final service = _HookedNotificationService((_) async {
          if (!showEntered.isCompleted) showEntered.complete();
          await releaseShow.future;
        });
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          platform: TargetPlatform.macOS,
          now: () => now,
          pendingClaimWait: Duration.zero,
          pendingMessageClaimTtl: const Duration(seconds: 60),
          pendingToneReservationWait: Duration.zero,
          pendingToneReservationTtl: const Duration(seconds: 60),
        );

        Future<void> show(String messageId) => maybeShowNotification(
          notificationService: service,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-delayed-show',
          senderUsername: 'Alice',
          messageText: messageId,
          messageId: messageId,
          durableNotificationCoordinatorResolver: () async => coordinator,
        );

        final first = show('message-delayed-1');
        await showEntered.future;
        final claimFile = File(
          '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'message-delayed-1')}',
        );
        expect(
          claimFile.readAsStringSync(),
          contains('"state":"pending"'),
          reason: 'non-Android ownership keeps its prior pending protocol',
        );
        expect(
          _onlyPendingToneFile(directory).readAsStringSync(),
          contains('"state":"pending"'),
        );

        now = now.add(const Duration(seconds: 30));
        expect(
          await DurableNotificationToneLease(
            directory: directory,
            now: () => now,
            pendingToneReservationWait: Duration.zero,
            pendingToneReservationTtl: const Duration(seconds: 60),
          ).reserveTone('peer-delayed-show'),
          isNull,
          reason: 'a normal delayed show must retain its audible reservation',
        );

        releaseShow.complete();
        await first;
        expect(service.shown.single.silent, isFalse);
        expect(claimFile.readAsStringSync(), contains('"state":"committed"'));
        expect(_pendingToneFiles(directory), isEmpty);

        now = now.add(const Duration(seconds: 9));
        await show('message-delayed-2');
        now = now.add(const Duration(seconds: 1));
        await show('message-delayed-3');
        expect(service.shown.map((item) => item.silent), <bool>[
          false,
          true,
          false,
        ]);
      },
    );

    test(
      'post-create exact-claim write failure fails open without residue',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'live-notification-claim-write-failure-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
          exclusiveClaimWriter: (file, contents) async {
            await file.writeAsString('{partial', flush: true);
            throw const FileSystemException('synthetic claim flush failure');
          },
        );
        final claimFile = File(
          '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'message-storage-fail-open')}',
        );

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-storage-fail-open',
          senderUsername: 'Alice',
          messageText: 'Still visible',
          messageId: 'message-storage-fail-open',
          durableNotificationCoordinatorResolver: () async => coordinator,
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.single.silent, isFalse);
        expect(claimFile.existsSync(), isFalse);
        final later =
            await DurableNotificationToneLease(
              directory: directory,
              pendingClaimWait: Duration.zero,
            ).claimMessageEvent(
              type: 'new_message',
              eventIdentity: 'message-storage-fail-open',
            );
        expect(later, isNotNull);
      },
    );

    test(
      'post-show reaction commit failures retain owners and never release',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'live-notification-commit-failure-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final claimFile = File(
          '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity('reaction-commit-failure'))}',
        );
        final service = _HookedNotificationService((_) async {
          await _replacePendingToken(claimFile, 'replacement-claim-owner');
          await _replacePendingToken(
            _onlyPendingToneFile(directory),
            'replacement-tone-owner',
          );
        });
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
          pendingToneReservationWait: Duration.zero,
        );

        await maybeShowNotification(
          notificationService: service,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:commit-failure',
          routePayload: 'group:commit-failure|message:message-commit-failure',
          senderUsername: 'Announcements',
          messageText: 'Admin update',
          messageId: 'reaction-commit-failure',
          notificationEventIdentity: boundedReactionEventIdentity(
            'reaction-commit-failure',
          ),
          notificationEventType: 'message_reaction',
          durableNotificationCoordinatorResolver: () async => coordinator,
        );

        expect(service.shown, hasLength(1));
        expect(
          claimFile.readAsStringSync(),
          contains('replacement-claim-owner'),
        );
        expect(
          _onlyPendingToneFile(directory).readAsStringSync(),
          contains('replacement-tone-owner'),
        );
        expect(
          events.map((event) => event['event']),
          containsAll(<String>[
            'NOTIFICATION_TONE_RESERVATION_COMMIT_FAILED',
            'NOTIFICATION_CLAIM_COMMIT_FAILED',
          ]),
        );
        final eventNames = events.map((event) => event['event']);
        expect(
          eventNames,
          isNot(contains('NOTIFICATION_TONE_RESERVATION_RELEASE_FAILED')),
        );
        expect(
          eventNames,
          isNot(contains('NOTIFICATION_CLAIM_RELEASE_FAILED')),
        );
      },
    );

    test('non-Android show failure attempts both exact-owner releases', () async {
      final directory = await Directory.systemTemp.createTemp(
        'live-notification-release-failure-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final claimFile = File(
        '${directory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/'
        '${DurableNotificationToneLease.messageEventClaimFileName(type: 'new_message', eventIdentity: 'message-release-failure')}',
      );
      final service = _HookedNotificationService((_) async {
        await _replacePendingToken(claimFile, 'replacement-claim-owner');
        await _replacePendingToken(
          _onlyPendingToneFile(directory),
          'replacement-tone-owner',
        );
        throw StateError('synthetic display failure');
      });
      final coordinator = DurableNotificationToneLease(
        directory: directory,
        platform: TargetPlatform.macOS,
        pendingClaimWait: Duration.zero,
        pendingToneReservationWait: Duration.zero,
      );

      await expectLater(
        maybeShowNotification(
          notificationService: service,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-release-failure',
          senderUsername: 'Alice',
          messageText: 'Will fail',
          messageId: 'message-release-failure',
          durableNotificationCoordinatorResolver: () async => coordinator,
        ),
        throwsA(isA<StateError>()),
      );

      expect(service.shown, isEmpty);
      expect(claimFile.readAsStringSync(), contains('replacement-claim-owner'));
      expect(
        _onlyPendingToneFile(directory).readAsStringSync(),
        contains('replacement-tone-owner'),
      );
      expect(
        events.map((event) => event['event']),
        containsAll(<String>[
          'NOTIFICATION_TONE_RESERVATION_RELEASE_FAILED',
          'NOTIFICATION_CLAIM_RELEASE_FAILED',
        ]),
      );
    });

    test(
      'reaction bursts debounce per conversation while different peers stay audible',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'live-notification-independent-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final start = Completer<void>();
        var toneWrites = 0;
        DurableNotificationToneLease coordinator() =>
            DurableNotificationToneLease(
              directory: directory,
              beforeToneWrite: () async => toneWrites++,
            );

        Future<void> produce({
          required String peerId,
          required String messageId,
        }) async {
          await start.future;
          await maybeShowNotification(
            notificationService: notificationService,
            conversationTracker: tracker,
            getAppLifecycleState: () => AppLifecycleState.paused,
            contactPeerId: peerId,
            senderUsername: peerId,
            messageText: messageId,
            messageId: messageId,
            notificationEventIdentity: boundedReactionEventIdentity(messageId),
            notificationEventType: 'message_reaction',
            durableNotificationCoordinatorResolver: () async => coordinator(),
          );
        }

        final producers = [
          produce(peerId: 'peer-independent-a', messageId: 'message-a'),
          produce(peerId: 'peer-independent-b', messageId: 'message-b'),
        ];
        start.complete();
        await Future.wait(producers);

        expect(notificationService.shown, hasLength(2));
        expect(notificationService.shown.every((item) => !item.silent), isTrue);
        expect(toneWrites, 2);

        await produce(peerId: 'peer-burst', messageId: 'reaction-burst-a');
        await produce(peerId: 'peer-burst', messageId: 'reaction-burst-b');
        expect(notificationService.shown, hasLength(4));
        expect(notificationService.shown.map((item) => item.silent), <bool>[
          false,
          false,
          false,
          true,
        ]);
        expect(toneWrites, 3);
      },
    );

    test(
      'claim storage unavailability fails open to legacy delivery',
      () async {
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-storage-unavailable',
          senderUsername: 'Alice',
          messageText: 'Still deliver',
          messageId: 'message-storage-unavailable',
          durableNotificationCoordinatorResolver: () async =>
              throw const FileSystemException('claim directory unavailable'),
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.single.silent, isFalse);
      },
    );

    test(
      'keeps group payload contract for local group notifications',
      () async {
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:group-123',
          routePayload: 'group:group-123|message:msg-123',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
        );

        expect(notificationService.shown, hasLength(1));
        expect(
          notificationService.shown.first.contactPeerId,
          'group:group-123',
        );
        expect(
          notificationService.shown.first.payload,
          'group:group-123|message:msg-123',
        );
        expect(notificationService.shown.first.senderUsername, 'Team Chat');
        expect(
          notificationService.shown.first.messageText,
          'Alice: Hello group!',
        );
      },
    );

    test('shows notification when app is backgrounded', () async {
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
        contactPeerId: 'peer-123',
        senderUsername: 'Alice',
        messageText: 'Hello!',
      );

      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.first.senderUsername, 'Alice');
      expect(notificationService.shown.first.messageText, 'Hello!');
    });

    test(
      'durable event claim suppresses a competing reaction producer',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'reaction-event-claim-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final coordinator = DurableNotificationToneLease(
          directory: directory,
          pendingClaimWait: Duration.zero,
        );
        final identity = boundedReactionEventIdentity('reaction-event-1');
        final existing = await coordinator.claimMessageEvent(
          type: 'message_reaction',
          eventIdentity: identity,
        );
        expect(existing, isNotNull);
        expect(await existing!.commit(), isTrue);

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-reactor',
          senderUsername: 'Alice',
          messageText: 'Reacted 👍 to your message',
          messageId: 'reaction-event-1',
          notificationEventIdentity: identity,
          notificationEventType: 'message_reaction',
          durableNotificationCoordinatorResolver: () async => coordinator,
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'durable tone denial keeps a distinct reaction card update silent',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'reaction-tone-denial-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final coordinator = DurableNotificationToneLease(directory: directory);
        final existingTone = await coordinator.reserveTone('peer-reactor');
        expect(existingTone, isNotNull);
        expect(await existingTone!.commit(), isTrue);

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-reactor',
          senderUsername: 'Alice',
          messageText: 'Reacted ❤️ to your message',
          messageId: 'reaction-event-2',
          notificationEventIdentity: boundedReactionEventIdentity(
            'reaction-event-2',
          ),
          notificationEventType: 'message_reaction',
          durableNotificationCoordinatorResolver: () async => coordinator,
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.single.silent, isTrue);
      },
    );

    test(
      'suppresses background local notification when a recent remote push already announced the same conversation',
      () async {
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async => true,
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'suppresses resumed local notification when a recent remote push already announced the same group message',
      () async {
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'group:group-123',
          routePayload: 'group:group-123|message:msg-123',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
          messageId: 'msg-123',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async {
                expect(payload, 'group:group-123|message:msg-123');
                expect(messageId, 'msg-123');
                return true;
              },
          backgroundDuplicateGuardDelay: const Duration(minutes: 5),
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'suppresses local group reaction when recent remote event matches',
      () async {
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:group-397',
          routePayload: 'group:group-397|message:group-target-message-397',
          senderUsername: 'Plan 397 Chat',
          messageText: 'Alice reacted',
          messageId: 'group-reaction-event-397',
          notificationEventIdentity: boundedReactionEventIdentity(
            'group-reaction-event-397',
          ),
          notificationEventType: 'message_reaction',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async {
                expect(
                  payload,
                  'group:group-397|message:group-target-message-397',
                );
                expect(messageId, 'group-reaction-event-397');
                return true;
              },
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test('suppresses notification during recovery replay', () async {
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        contactPeerId: 'peer-123',
        senderUsername: 'Alice',
        messageText: 'Hello!',
        suppressNotification: true,
      );

      expect(notificationService.shown, isEmpty);
    });

    test(
      'resume-only recovery suppression does not synthesize a tap route',
      () async {
        final events = <Map<String, dynamic>>[];
        var routeCalls = 0;
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        notificationService.onNotificationTap = (_) {
          routeCalls += 1;
        };

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Recovered from inbox',
          suppressNotification: true,
        );

        expect(notificationService.shown, isEmpty);
        expect(routeCalls, 0);
        expect(
          events,
          contains(
            predicate<Map<String, dynamic>>((event) {
              final details = event['details'];
              return event['event'] == 'NOTIFICATION_SUPPRESSED' &&
                  details is Map &&
                  details['reason'] == 'recovery_replay';
            }),
          ),
        );
      },
    );

    test(
      'prefers exact message-id suppression over route-wide suppression when available',
      () async {
        var capturedPayload = '';
        String? capturedMessageId;

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'msg-123',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async {
                capturedPayload = payload;
                capturedMessageId = messageId;
                return true;
              },
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, isEmpty);
        expect(capturedPayload, 'peer-123');
        expect(capturedMessageId, 'msg-123');
      },
    );

    test('uses route payload for remote suppression when present', () async {
      var capturedPayload = '';
      String? capturedMessageId;

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
        contactPeerId: 'group:group-123',
        routePayload: 'group:group-123|message:msg-123',
        senderUsername: 'Team Chat',
        messageText: 'Alice: Hello group!',
        messageId: 'msg-123',
        consumeRecentRemoteNotificationAnnouncement:
            ({required payload, String? messageId}) async {
              capturedPayload = payload;
              capturedMessageId = messageId;
              return true;
            },
        backgroundDuplicateGuardDelay: Duration.zero,
      );

      expect(notificationService.shown, isEmpty);
      expect(capturedPayload, 'group:group-123|message:msg-123');
      expect(capturedMessageId, 'msg-123');
    });

    test(
      'GIRD-006 suppresses only the exact remotely announced group message',
      () async {
        final announced = <String>{'group:group-123|message:msg-remote'};

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:group-123',
          routePayload: 'group:group-123|message:msg-remote',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Photo',
          messageId: 'msg-remote',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async {
                expect(messageId, 'msg-remote');
                return announced.remove(payload);
              },
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:group-123',
          routePayload: 'group:group-123|message:msg-local',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Photo',
          messageId: 'msg-local',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async {
                expect(messageId, 'msg-local');
                return announced.remove(payload);
              },
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, hasLength(1));
        expect(
          notificationService.shown.single.payload,
          'group:group-123|message:msg-local',
        );
      },
    );

    test(
      'preserves mixed-script sender and body when forwarding notification text',
      () async {
        const sender = '\u0644\u064a\u0644\u0649 Alpha';
        const body = '\u0645\u0631\u062d\u0628\u0627 Team 42';

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-123',
          senderUsername: sender,
          messageText: body,
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.first.senderUsername, sender);
        expect(notificationService.shown.first.messageText, body);
        expect(notificationService.shown.first.payload, 'peer-123');
      },
    );

    test(
      'preserves bidi control marks in mixed-script body passthrough',
      () async {
        const body = '\u200f\u0645\u0631\u062d\u0628\u0627 Alpha\u200f';

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: body,
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.first.messageText, body);
      },
    );

    test(
      'shows notification when app is resumed but on different screen',
      () async {
        // Not viewing any conversation
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
        );

        expect(notificationService.shown, hasLength(1));
      },
    );

    test(
      'shows notification when app is resumed and viewing a different conversation',
      () async {
        tracker.setActive('peer-456'); // viewing someone else

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
        );

        expect(notificationService.shown, hasLength(1));
      },
    );

    test(
      'suppresses notification when app is resumed and viewing active 1:1 conversation',
      () async {
        tracker.setActive('peer-123'); // viewing sender's conversation

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'suppresses notification when app is resumed and viewing active group conversation',
      () async {
        tracker.setActive('group:group-123');

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'group:group-123',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'suppresses active group notification when the contact key is message anchored',
      () async {
        tracker.setActive('group:group-123');

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'group:group-123|message:msg-123',
          routePayload: 'group:group-123|message:msg-123',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'suppresses active group notification using the anchored route payload',
      () async {
        tracker.setActive('group:group-123');

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'group:group-123',
          routePayload: 'group:group-123|message:msg-123',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test('shows notification when app is inactive (not resumed)', () async {
      tracker.setActive('peer-123');

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.inactive,
        contactPeerId: 'peer-123',
        senderUsername: 'Alice',
        messageText: 'Hello!',
      );

      expect(notificationService.shown, hasLength(1));
    });

    test('shows notification after clearing active conversation', () async {
      tracker.setActive('peer-123');
      tracker.clear();

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        contactPeerId: 'peer-123',
        senderUsername: 'Alice',
        messageText: 'Hello!',
      );

      expect(notificationService.shown, hasLength(1));
    });

    // 118 Phase 2: gate contract lock + live-wins FCM dedup handshake.
    test(
      'emits the provided suppressionReason instead of the default literal',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          suppressNotification: true,
          suppressionReason: 'genuine_recovery_drain',
        );

        expect(notificationService.shown, isEmpty);
        expect(
          events,
          contains(
            predicate<Map<String, dynamic>>((event) {
              final details = event['details'];
              return event['event'] == 'NOTIFICATION_SUPPRESSED' &&
                  details is Map &&
                  details['reason'] == 'genuine_recovery_drain';
            }),
          ),
        );
      },
    );

    test('live path writes a live-wins dedup marker so a late FCM isolate '
        'suppresses the same messageId', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mknoon_dedup_marker_test',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final gate = RecentRemoteNotificationGate(
        filePath: '${tempDir.path}/gate.json',
      );

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        contactPeerId: 'peer-123',
        senderUsername: 'Alice',
        messageText: 'Hello!',
        messageId: 'm1',
        markRecentRemoteNotificationAnnouncement:
            ({required payload, String? messageId}) =>
                gate.markAnnouncement(payload: payload, messageId: messageId),
      );

      // The live message showed AND its marker is now recorded.
      expect(notificationService.shown, hasLength(1));

      // A late FCM background isolate consuming the SAME (payload|messageId)
      // finds-and-suppresses, preventing a second notification.
      final lateFcmWouldSuppress = await gate.consumeIfRecentAnnouncement(
        payload: 'peer-123',
        messageId: 'm1',
      );
      expect(lateFcmWouldSuppress, isTrue);
    });

    test('live path does NOT write a dedup marker when messageId is absent '
        '(no over-suppression of unrelated payload messages)', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mknoon_dedup_marker_test_noid',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final gate = RecentRemoteNotificationGate(
        filePath: '${tempDir.path}/gate.json',
      );

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        contactPeerId: 'peer-123',
        senderUsername: 'Alice',
        messageText: 'Hello!',
        // no messageId
        markRecentRemoteNotificationAnnouncement:
            ({required payload, String? messageId}) =>
                gate.markAnnouncement(payload: payload, messageId: messageId),
      );

      expect(notificationService.shown, hasLength(1));
      final wouldSuppress = await gate.consumeIfRecentAnnouncement(
        payload: 'peer-123',
      );
      expect(wouldSuppress, isFalse);
    });
  });

  // 118 Phase 5 (VERIFICATION/CHARACTERIZATION): these lock that the live↔FCM
  // dedup race does not double-notify, in BOTH orderings, against the Phase 1+2
  // code with no further production change. A failure here would be the signal
  // that a real fix is needed.
  group('118 Phase 5: live <-> FCM dedup-race characterization', () {
    late Directory tempDir;
    late RecentRemoteNotificationGate gate;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mknoon_p5_dedup');
      gate = RecentRemoteNotificationGate(
        filePath: '${tempDir.path}/gate.json',
      );
    });
    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<bool> consume({required String payload, String? messageId}) => gate
        .consumeIfRecentAnnouncement(payload: payload, messageId: messageId);
    Future<void> mark({required String payload, String? messageId}) =>
        gate.markAnnouncement(payload: payload, messageId: messageId);

    test(
      'live direct then FCM drain (same messageId) does not double-notify',
      () async {
        // Live-first: resumed-but-not-viewing shows AND writes the marker.
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-1',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'm1',
          consumeRecentRemoteNotificationAnnouncement: consume,
          markRecentRemoteNotificationAnnouncement: mark,
          backgroundDuplicateGuardDelay: Duration.zero,
        );
        expect(notificationService.shown, hasLength(1));

        // The late FCM drain of the SAME messageId consumes the marker and
        // suppresses with reason recent_remote_push.
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-1',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'm1',
          consumeRecentRemoteNotificationAnnouncement: consume,
          markRecentRemoteNotificationAnnouncement: mark,
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, hasLength(1));
        expect(
          events,
          contains(
            predicate<Map<String, dynamic>>((event) {
              final details = event['details'];
              return event['event'] == 'NOTIFICATION_SUPPRESSED' &&
                  details is Map &&
                  details['reason'] == 'recent_remote_push';
            }),
          ),
        );
      },
    );

    test(
      'FCM then live direct (same messageId) does not double-notify',
      () async {
        // FCM-first: the background isolate marked the announcement.
        await mark(payload: 'peer-1', messageId: 'm1');

        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        // Later live direct consumes it -> suppressed (existing FCM-first gate).
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-1',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'm1',
          consumeRecentRemoteNotificationAnnouncement: consume,
          markRecentRemoteNotificationAnnouncement: mark,
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, isEmpty);
        expect(
          events,
          contains(
            predicate<Map<String, dynamic>>((event) {
              final details = event['details'];
              return event['event'] == 'NOTIFICATION_SUPPRESSED' &&
                  details is Map &&
                  details['reason'] == 'recent_remote_push';
            }),
          ),
        );
      },
    );

    test('resumed-but-not-viewing path is not delayed by the background guard '
        '(a 10-minute guard would time out if slept)', () async {
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        contactPeerId: 'peer-1',
        senderUsername: 'Alice',
        messageText: 'Hello!',
        messageId: 'm1',
        consumeRecentRemoteNotificationAnnouncement: consume,
        markRecentRemoteNotificationAnnouncement: mark,
        backgroundDuplicateGuardDelay: const Duration(minutes: 10),
      );

      expect(notificationService.shown, hasLength(1));
    });
  });

  // 118 Phase 4: at most one audible tone per conversation per window; the
  // tone key is normalizeActiveKey(contactPeerId), NOT the per-message route.
  group('118 Phase 4: per-conversation tone debounce', () {
    late DateTime now;
    late NotificationToneTracker toneTracker;

    setUp(() {
      now = DateTime.utc(2026, 6, 13, 12);
      toneTracker = NotificationToneTracker(
        clock: () => now,
        window: const Duration(seconds: 10),
      );
    });

    Future<void> showLive({
      required String contactPeerId,
      required String messageId,
      String? routePayload,
    }) {
      return maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        contactPeerId: contactPeerId,
        routePayload: routePayload,
        senderUsername: 'Alice',
        messageText: 'Hello!',
        messageId: messageId,
        toneTracker: toneTracker,
      );
    }

    test('first live message sounds, second within window is silent', () async {
      await showLive(contactPeerId: 'peer-1', messageId: 'm1');
      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.last.silent, isFalse);

      now = now.add(const Duration(seconds: 5));
      await showLive(contactPeerId: 'peer-1', messageId: 'm2');
      expect(notificationService.shown, hasLength(2));
      expect(notificationService.shown.last.silent, isTrue);
    });

    test('first live message after the window sounds again', () async {
      await showLive(contactPeerId: 'peer-1', messageId: 'm1');
      now = now.add(const Duration(seconds: 10));
      await showLive(contactPeerId: 'peer-1', messageId: 'm2');
      expect(notificationService.shown.map((s) => s.silent).toList(), <bool>[
        false,
        false,
      ]);
    });

    test(
      'a viewed (suppressed) message never consumes the tone window',
      () async {
        tracker.setActive(
          'peer-1',
        ); // viewing -> suppressed before tone decision
        await showLive(contactPeerId: 'peer-1', messageId: 'm1');
        expect(notificationService.shown, isEmpty);

        tracker.clear();
        await showLive(contactPeerId: 'peer-1', messageId: 'm2');
        expect(notificationService.shown, hasLength(1));
        // The first real message still gets a tone — the suppressed one did not
        // touch shouldPlayTone.
        expect(notificationService.shown.last.silent, isFalse);
      },
    );

    test(
      'group burst is single-tone keyed on the group, not the per-message route',
      () async {
        await showLive(
          contactPeerId: 'group:g1',
          routePayload: 'group:g1|message:a',
          messageId: 'a',
        );
        expect(notificationService.shown.last.silent, isFalse);

        now = now.add(const Duration(seconds: 5));
        await showLive(
          contactPeerId: 'group:g1',
          routePayload: 'group:g1|message:b',
          messageId: 'b',
        );
        // Same group, different routePayload -> still within the window -> silent.
        expect(notificationService.shown.last.silent, isTrue);
      },
    );

    test(
      'when no tone tracker is wired, behavior is unchanged (audible)',
      () async {
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-1',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'm1',
        );
        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.last.silent, isFalse);
      },
    );
  });

  group('ActiveConversationTracker', () {
    test('isViewing returns false by default', () {
      expect(tracker.isViewing('any-peer'), isFalse);
    });

    test('isViewing returns true after setActive', () {
      tracker.setActive('peer-123');
      expect(tracker.isViewing('peer-123'), isTrue);
      expect(tracker.isViewing('peer-456'), isFalse);
    });

    test('isViewing returns false after clear', () {
      tracker.setActive('peer-123');
      tracker.clear();
      expect(tracker.isViewing('peer-123'), isFalse);
    });

    test('setActive replaces previous peer', () {
      tracker.setActive('peer-123');
      tracker.setActive('peer-456');
      expect(tracker.isViewing('peer-123'), isFalse);
      expect(tracker.isViewing('peer-456'), isTrue);
    });

    test('clearIfActive only clears the matching active key', () {
      tracker.setActive('peer-123');
      tracker.clearIfActive('peer-456');
      expect(tracker.isViewing('peer-123'), isTrue);

      tracker.clearIfActive('peer-123');
      expect(tracker.isViewing('peer-123'), isFalse);
    });

    test('clearIfActive normalizes anchored group route keys', () {
      tracker.setActive('group:group-123');
      tracker.clearIfActive('group:group-456|message:msg-456');
      expect(tracker.isViewing('group:group-123'), isTrue);

      tracker.clearIfActive('group:group-123|message:msg-123');
      expect(tracker.isViewing('group:group-123'), isFalse);
    });
  });
}

final class _DurableBoundaryNotificationService extends FakeNotificationService
    implements
        MessageNotificationDurableFinalEffectBoundary,
        MessageNotificationDurablePostHandoffReconciliation {
  _DurableBoundaryNotificationService({
    required this.log,
    this.terminalReplay = false,
    this.beforeAuthorize,
  });

  final List<String> log;
  final bool terminalReplay;
  final Future<void> Function()? beforeAuthorize;
  int nativeCalls = 0;

  @override
  Future<void> notifyDurableEffectHandoffComplete(
    DurableLocalNotificationEffectReceipt receipt,
  ) async {
    log.add('reconcile');
  }

  @override
  Future<DurableLocalNotificationEffectResult>
  showMessageNotificationWithDurableFinalEffect({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    required ConversationNotificationContentKind contentKind,
    required String contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
    required DurableLocalNotificationEffectContext durableEffectContext,
    required AppVisibilitySuppressionReader finalVisibility,
    required AppVisibilityConversationIdentity conversationIdentity,
    required PublishNativeMessageNotificationAtDurableBarrier publishNative,
  }) async {
    if (terminalReplay || durableEffectContext.remotePresentationEstablished) {
      log.add('service_return');
      return DurableLocalNotificationEffectResult(
        disposition: DurableLocalNotificationEffectDisposition.osPosted,
        receipt: DurableLocalNotificationEffectReceipt(
          eventCorrelation: durableEffectContext.eventCorrelation,
          recordRevision: 4,
          presentationState: LocalNotificationPresentationState.osPosted,
        ),
      );
    }
    late AppVisibilityEvaluation finalEvaluation;
    late final LocalNotificationPresentationState presentation;
    late final DurableLocalNotificationEffectDisposition disposition;
    final entered = await publishNative(
      ({required bool silent}) async {
        nativeCalls += 1;
        log.add('native');
      },
      () async {
        await beforeAuthorize?.call();
        finalEvaluation = await finalVisibility.evaluate(conversationIdentity);
        return !finalEvaluation.maySuppress;
      },
    );
    if (!entered && finalEvaluation.maySuppress) {
      presentation = LocalNotificationPresentationState.inChat;
      disposition = DurableLocalNotificationEffectDisposition.inChat;
    } else {
      presentation = LocalNotificationPresentationState.osPosted;
      disposition = DurableLocalNotificationEffectDisposition.osPosted;
    }
    log.add('service_return');
    return DurableLocalNotificationEffectResult(
      disposition: disposition,
      currentNativeEntryAttempted: entered,
      receipt: DurableLocalNotificationEffectReceipt(
        eventCorrelation: durableEffectContext.eventCorrelation,
        recordRevision: 4,
        presentationState: presentation,
      ),
    );
  }
}

final class _NativeBoundaryNotificationService extends FakeNotificationService
    implements MessageNotificationNativePublicationBoundary {
  final Completer<void> nativeBoundaryEntered = Completer<void>();
  final Completer<void> releaseNativeBoundary = Completer<void>();
  int nativeCalls = 0;

  @override
  Future<void> showMessageNotificationAtNativeBoundary({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
    required Future<void> Function(NativeMessageNotificationShow showNative)
    publishNative,
  }) async {
    if (!nativeBoundaryEntered.isCompleted) nativeBoundaryEntered.complete();
    await releaseNativeBoundary.future;
    await publishNative(({required bool silent}) async {
      nativeCalls += 1;
    });
  }
}

final class _SequencedVisibility extends AppVisibilitySuppressionReader {
  _SequencedVisibility(this._evaluations);

  final List<AppVisibilityEvaluation> _evaluations;
  int evaluations = 0;

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async {
    final index = evaluations++;
    return _evaluations[index];
  }
}

AppVisibilityEvaluation _exactForegroundEvaluation({
  required bool maySuppress,
  required int revision,
}) => AppVisibilityEvaluation(
  isForegroundActive: true,
  maySuppress: maySuppress,
  lifecycle: AppVisibilityLifecycle.foregroundActive,
  revision: revision,
  lifecycleGeneration: revision,
);

AppVisibilityEvaluation _exactBackgroundEvaluation({required int revision}) =>
    AppVisibilityEvaluation(
      isForegroundActive: false,
      maySuppress: false,
      lifecycle: AppVisibilityLifecycle.background,
      revision: revision,
      lifecycleGeneration: revision,
    );

class _HookedNotificationService extends FakeNotificationService {
  _HookedNotificationService(this._beforeShow);

  final Future<void> Function(int attempt) _beforeShow;
  int attempts = 0;

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
  }) async {
    attempts += 1;
    await _beforeShow(attempts);
    await super.showMessageNotification(
      contactPeerId: contactPeerId,
      senderUsername: senderUsername,
      messageText: messageText,
      payload: payload,
      silent: silent,
      contentKind: contentKind,
      contentEventIdentity: contentEventIdentity,
      snapshot: snapshot,
    );
  }
}

List<File> _pendingToneFiles(Directory root) {
  final directory = Directory(
    '${root.path}/${DurableNotificationToneLease.toneLeasesDirectoryName}',
  );
  if (!directory.existsSync()) return const <File>[];
  return directory
      .listSync()
      .whereType<File>()
      .where(
        (file) => file.path.endsWith(
          DurableNotificationToneLease.tonePendingReservationFileSuffix,
        ),
      )
      .toList(growable: false);
}

File _onlyPendingToneFile(Directory root) => _pendingToneFiles(root).single;

Future<void> _replacePendingToken(File file, String token) async {
  final record = Map<String, Object?>.from(
    jsonDecode(await file.readAsString()) as Map,
  );
  record['token'] = token;
  await file.writeAsString(jsonEncode(record), flush: true);
}
