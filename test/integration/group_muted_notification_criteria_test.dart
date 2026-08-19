import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_muted_notification_android_criteria.dart';
import '../../integration_test/scripts/group_reaction_notification_device_criteria.dart';

/// Plan 379 muted-group device lane, host tier.
///
/// Every negative below is the happy artifact with exactly ONE field changed,
/// produced by the SAME [buildGroupMutedNotificationArtifact] the capture
/// stages call. A fixture-keyed validator (one that only recognizes
/// hand-written negatives) therefore cannot pass this suite.
void main() {
  late Directory proofDirectory;

  setUp(() {
    proofDirectory = Directory.systemTemp.createTempSync('plan379-muted-');
  });

  tearDown(() {
    if (proofDirectory.existsSync()) {
      proofDirectory.deleteSync(recursive: true);
    }
  });

  Future<GroupMutedNotificationArtifactValidation> validate(
    GroupMutedNotificationCaptureInput input, {
    Map<String, Object?> Function(Map<String, Object?> artifact)? mutate,
  }) async {
    var artifact = await buildGroupMutedNotificationArtifact(
      proofDirectory: proofDirectory,
      input: input,
    );
    if (mutate != null) artifact = mutate(artifact);
    final artifactFile = File(
      '${proofDirectory.path}${Platform.pathSeparator}${input.scenario}.json',
    );
    await artifactFile.writeAsString(jsonEncode(artifact));
    return validateGroupMutedNotificationAndroidArtifact(
      artifactFile: artifactFile,
    );
  }

  group('Plan 379 muted-group artifact validator', () {
    test('accepts the live muted-message happy artifact', () async {
      final validation = await validate(happyMutedMessageCaptureInput());

      expect(validation.ok, isTrue, reason: validation.detail);
    });

    test('accepts the background muted-reaction happy artifact', () async {
      final validation = await validate(happyMutedReactionCaptureInput());

      expect(validation.ok, isTrue, reason: validation.detail);
    });

    test('rejects an artifact whose unread did not grow past the '
        'baseline', () async {
      // Shared with the contract shell so the two tiers cannot disagree about
      // what a rejected muted artifact is. The raw probe observation moves
      // with the summary: mutating only the summary is caught by the
      // raw-vs-summary cross-check instead, leaving the growth rule untested
      // (mutation M3 passed until this negative was made consistent).
      final validation = await validate(
        unreadUnchangedMutedMessageCaptureInput(),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('unread'));
    });

    test(
      'rejects a background artifact with no persisted reaction row',
      () async {
        final happy = happyMutedReactionCaptureInput();
        final validation = await validate(
          happy.copyWith(
            mutedProjection: happy.mutedProjection.copyWith(
              reactionRowsObserved: 0,
            ),
          ),
        );

        expect(validation.ok, isFalse);
        expect(validation.detail, contains('reactionRowsObserved'));
      },
    );

    test('rejects any artifact whose unread regressed below the '
        'baseline', () async {
      final happy = happyMutedReactionCaptureInput();
      final validation = await validate(
        happy.copyWith(
          mutedProjection: happy.mutedProjection.copyWith(
            unreadAfter: 0,
            sqlcipherObservation: sqlcipherObservationFixture(
              groupIsMuted: true,
              unreadCount: 0,
              badgeAvailable: true,
              badgeIncludesObservedGroup: false,
            ),
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('unread'));
    });

    test('does not demand unread growth on the background lane', () async {
      // The FCM lane's target message is recipient-authored, so requiring
      // growth there would make a correct capture unpassable. Equal
      // baseline/after must be accepted.
      final happy = happyMutedReactionCaptureInput();

      expect(
        happy.mutedProjection.unreadAfter,
        happy.mutedProjection.unreadBaseline,
      );
      expect((await validate(happy)).ok, isTrue);
    });

    test(
      'rejects an artifact whose message under test was marked read',
      () async {
        final happy = happyMutedMessageCaptureInput();
        final validation = await validate(
          happy.copyWith(
            mutedProjection: happy.mutedProjection.copyWith(
              underTestReadAtNull: false,
            ),
          ),
        );

        expect(validation.ok, isFalse);
        expect(validation.detail, contains('read_at'));
      },
    );

    test('rejects a declared active card for the muted group', () async {
      final happy = happyMutedMessageCaptureInput();
      final validation = await validate(
        happy.copyWith(
          mutedProjection: happy.mutedProjection.copyWith(mutedCardCount: 1),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('mutedCardCount'));
    });

    test('rejects a summary claiming zero cards while the raw dump still '
        'shows one', () async {
      final happy = happyMutedMessageCaptureInput();
      final leaking = happy.copyWith(
        mutedProjection: happy.mutedProjection.copyWith(
          notificationDump: mutedNotificationDumpFixture(
            packageName: happy.build.packageName,
            controlGroupName: happy.fixture.controlGroupName,
            controlMarker: happy.control.controlMarker,
            leakedMutedGroupName: happy.fixture.mutedGroupName,
            leakedMarker: happy.mutedProjection.underTestMarker,
          ),
        ),
      );

      final validation = await validate(leaking);

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('raw'));
    });

    test(
      'rejects a raw dump that no longer contains the control card',
      () async {
        final happy = happyMutedMessageCaptureInput();
        final validation = await validate(
          happy.copyWith(
            mutedProjection: happy.mutedProjection.copyWith(
              // A real dump with a real app card — just not the control
              // group's. Without this the "no control card" branch would be
              // unreachable behind the empty-dump guard.
              notificationDump: mutedNotificationDumpFixture(
                packageName: happy.build.packageName,
                controlGroupName: 'Plan379Z-Decoy77',
                controlMarker: 'Plan379DecoyMarker',
              ),
            ),
          ),
        );

        expect(validation.ok, isFalse);
        expect(validation.detail, contains('control'));
      },
    );

    test('rejects a badge state that still contains the muted group', () async {
      final happy = happyMutedMessageCaptureInput();
      final validation = await validate(
        happy.copyWith(
          mutedProjection: happy.mutedProjection.copyWith(
            badgeIncludesMutedGroup: true,
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('badge'));
    });

    test('rejects an unavailable badge projection', () async {
      final happy = happyMutedMessageCaptureInput();
      final validation = await validate(
        happy.copyWith(
          mutedProjection: happy.mutedProjection.copyWith(
            badgeAvailable: false,
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('badge'));
    });

    test(
      'rejects a badge state that dropped the unmuted control group',
      () async {
        final happy = happyMutedMessageCaptureInput();
        final validation = await validate(
          happy.copyWith(
            mutedProjection: happy.mutedProjection.copyWith(
              badgeIncludesControlGroup: false,
            ),
          ),
        );

        expect(validation.ok, isFalse);
        expect(validation.detail, contains('badge'));
      },
    );

    test('rejects a false groupIsMuted observation', () async {
      final happy = happyMutedMessageCaptureInput();
      final validation = await validate(
        happy.copyWith(
          mutedProjection: happy.mutedProjection.copyWith(groupIsMuted: false),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('groupIsMuted'));
    });

    test('rejects an artifact whose groupIsMuted key is absent', () async {
      final validation = await validate(
        happyMutedMessageCaptureInput(),
        mutate: (artifact) {
          final projection = Map<String, Object?>.from(
            artifact['mutedProjection']! as Map<String, Object?>,
          )..remove('groupIsMuted');
          return <String, Object?>{...artifact, 'mutedProjection': projection};
        },
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('groupIsMuted'));
    });

    test('rejects a missing pre-mute control card', () async {
      final happy = happyMutedMessageCaptureInput();
      final validation = await validate(
        happy.copyWith(control: happy.control.copyWith(preMuteCardCount: 0)),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('preMuteCardCount'));
    });

    test('rejects a missing post-mute lane-liveness control card', () async {
      final happy = happyMutedMessageCaptureInput();
      final validation = await validate(
        happy.copyWith(control: happy.control.copyWith(postMuteCardCount: 0)),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('postMuteCardCount'));
    });

    test(
      'rejects a background artifact missing PUSH_BACKGROUND_MESSAGE_RECEIVED '
      'for the control push',
      () async {
        final happy = happyMutedReactionCaptureInput();
        final delivery = happy.backgroundDelivery!;
        final validation = await validate(
          happy.copyWith(
            backgroundDelivery: delivery.copyWith(
              backgroundFlowLog: backgroundFlowLogFixture(
                mutedFcmMessageId: delivery.mutedFcmMessageId,
                controlFcmMessageId: null,
                suppressionReason: delivery.suppressionReason,
                suppressedFcmMessageId: delivery.mutedFcmMessageId,
              ),
            ),
          ),
        );

        expect(validation.ok, isFalse);
        expect(validation.detail, contains('PUSH_BACKGROUND_MESSAGE_RECEIVED'));
      },
    );

    test('rejects a background artifact whose suppression event binds a '
        'different message id', () async {
      final happy = happyMutedReactionCaptureInput();
      final delivery = happy.backgroundDelivery!;
      final validation = await validate(
        happy.copyWith(
          backgroundDelivery: delivery.copyWith(
            backgroundFlowLog: backgroundFlowLogFixture(
              mutedFcmMessageId: delivery.mutedFcmMessageId,
              controlFcmMessageId: delivery.controlFcmMessageId,
              suppressionReason: delivery.suppressionReason,
              suppressedFcmMessageId: delivery.controlFcmMessageId,
            ),
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(
        validation.detail,
        contains('PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED'),
      );
    });

    test('records the suppression reason without pinning the muted '
        'literal', () async {
      final happy = happyMutedReactionCaptureInput();
      final delivery = happy.backgroundDelivery!;
      final validation = await validate(
        happy.copyWith(
          backgroundDelivery: delivery.copyWith(
            suppressionReason: 'group_reaction_local_state_ineligible',
            backgroundFlowLog: backgroundFlowLogFixture(
              mutedFcmMessageId: delivery.mutedFcmMessageId,
              controlFcmMessageId: delivery.controlFcmMessageId,
              suppressionReason: 'group_reaction_local_state_ineligible',
              suppressedFcmMessageId: delivery.mutedFcmMessageId,
            ),
          ),
        ),
      );

      expect(validation.ok, isTrue, reason: validation.detail);
    });

    test('rejects a background artifact whose muted push is the FIRST '
        'post-kill wake', () async {
      final happy = happyMutedReactionCaptureInput();
      final delivery = happy.backgroundDelivery!;
      final validation = await validate(
        happy.copyWith(
          backgroundDelivery: delivery.copyWith(
            // Three wakes, but the muted push is the one that pays the cold
            // SQLCipher open. Its silence is then the display_eligibility
            // storage deferral, which fires UPSTREAM of the mute gate.
            backgroundFlowLog: backgroundFlowLogFixture(
              mutedFcmMessageId: delivery.mutedFcmMessageId,
              controlFcmMessageId: delivery.controlFcmMessageId,
              suppressionReason: delivery.suppressionReason,
              suppressedFcmMessageId: delivery.mutedFcmMessageId,
              warmupFcmMessageId: null,
              trailingWakeFcmMessageId: 'plan379-fcm-late-wake',
            ),
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('FIRST post-kill wake'));
      expect(validation.detail, isNot(contains('must land a warm-up wake')));
    });

    test('rejects a background artifact with no warm-up wake ahead of the '
        'graded pushes', () async {
      final happy = happyMutedReactionCaptureInput();
      final delivery = happy.backgroundDelivery!;
      final validation = await validate(
        happy.copyWith(
          backgroundDelivery: delivery.copyWith(
            backgroundFlowLog: backgroundFlowLogFixture(
              mutedFcmMessageId: delivery.mutedFcmMessageId,
              controlFcmMessageId: delivery.controlFcmMessageId,
              suppressionReason: delivery.suppressionReason,
              suppressedFcmMessageId: delivery.mutedFcmMessageId,
              warmupFcmMessageId: null,
            ),
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('must land a warm-up wake'));
    });

    test('rejects a background artifact whose control card is not bound to '
        'its own push', () async {
      final happy = happyMutedReactionCaptureInput();
      final delivery = happy.backgroundDelivery!;
      final validation = await validate(
        happy.copyWith(
          backgroundDelivery: delivery.copyWith(
            backgroundFlowLog: backgroundFlowLogFixture(
              mutedFcmMessageId: delivery.mutedFcmMessageId,
              controlFcmMessageId: delivery.controlFcmMessageId,
              suppressionReason: delivery.suppressionReason,
              suppressedFcmMessageId: delivery.mutedFcmMessageId,
              includeShownEvent: false,
            ),
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('PUSH_BACKGROUND_NOTIFICATION_SHOWN'));
    });

    test('rejects a background artifact that presented a card for the muted '
        'push', () async {
      final happy = happyMutedReactionCaptureInput();
      final delivery = happy.backgroundDelivery!;
      final validation = await validate(
        happy.copyWith(
          backgroundDelivery: delivery.copyWith(
            backgroundFlowLog: backgroundFlowLogFixture(
              mutedFcmMessageId: delivery.mutedFcmMessageId,
              controlFcmMessageId: delivery.controlFcmMessageId,
              suppressionReason: delivery.suppressionReason,
              suppressedFcmMessageId: delivery.mutedFcmMessageId,
              shownFcmMessageId: delivery.mutedFcmMessageId,
            ),
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(
        validation.detail,
        contains('presented a card for the muted push'),
      );
    });

    test('rejects a background artifact that reports a foregrounded '
        'recipient', () async {
      final happy = happyMutedReactionCaptureInput();
      final validation = await validate(
        happy.copyWith(
          backgroundDelivery: happy.backgroundDelivery!.copyWith(
            recipientProcessState: 'foreground',
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('recipientProcessState'));
    });

    test(
      'rejects the live scenario carrying background-delivery evidence',
      () async {
        final happy = happyMutedMessageCaptureInput();
        final validation = await validate(
          happy.copyWith(
            backgroundDelivery:
                happyMutedReactionCaptureInput().backgroundDelivery,
          ),
        );

        expect(validation.ok, isFalse);
      },
    );

    test('rejects an unregistered scenario id', () async {
      final happy = happyMutedMessageCaptureInput();
      final validation = await validate(
        happy.copyWith(scenario: 'android_group_reaction_recipient'),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('scenario'));
    });

    test('the muted artifact is rejected by the Plan 257 reaction '
        'validator', () async {
      final input = happyMutedMessageCaptureInput();
      final artifact = await buildGroupMutedNotificationArtifact(
        proofDirectory: proofDirectory,
        input: input,
      );
      final artifactFile = File(
        '${proofDirectory.path}${Platform.pathSeparator}${input.scenario}.json',
      );
      await artifactFile.writeAsString(jsonEncode(artifact));

      final reactionValidation =
          await validateGroupReactionNotificationArtifact(
            scenario: input.scenario,
            artifactFile: artifactFile,
          );

      expect(reactionValidation.ok, isFalse);
    });
  });

  group('Plan 379 background push binding', () {
    String logOf({
      String? warmup = plan379WarmupFcmMessageIdFixture,
      String muted = 'plan379-fcm-muted-push',
      String? control = 'plan379-fcm-control-push',
      String? shown = 'plan379-fcm-control-push',
      String suppressed = 'plan379-fcm-muted-push',
      bool includeShownEvent = true,
    }) => backgroundFlowLogFixture(
      mutedFcmMessageId: muted,
      controlFcmMessageId: control,
      suppressionReason: 'group_reaction_local_state_ineligible',
      suppressedFcmMessageId: suppressed,
      warmupFcmMessageId: warmup,
      shownFcmMessageId: shown,
      includeShownEvent: includeShownEvent,
    );

    test('binds the graded pushes and never the warm-up wake', () {
      final binding = resolveMutedBackgroundPushBinding(logOf());

      expect(binding, isNotNull);
      expect(binding!.warmupFcmMessageId, plan379WarmupFcmMessageIdFixture);
      expect(binding.mutedFcmMessageId, 'plan379-fcm-muted-push');
      expect(binding.controlFcmMessageId, 'plan379-fcm-control-push');
    });

    test('fails closed when only two wakes are recorded', () {
      expect(resolveMutedBackgroundPushBinding(logOf(warmup: null)), isNull);
    });

    test('fails closed when nothing was presented', () {
      expect(
        resolveMutedBackgroundPushBinding(logOf(includeShownEvent: false)),
        isNull,
      );
    });

    test('never binds the warm-up wake as the control push', () {
      // A warm-up that reached the presenter instead of deferring must not be
      // mistaken for the pipeline-health control.
      expect(
        resolveMutedBackgroundPushBinding(
          logOf(shown: plan379WarmupFcmMessageIdFixture),
        ),
        isNull,
      );
    });

    test('never binds the warm-up wake as the muted push', () {
      expect(
        resolveMutedBackgroundPushBinding(
          logOf(suppressed: plan379WarmupFcmMessageIdFixture),
        ),
        isNull,
      );
    });
  });

  group('Plan 384 killed-app card artifact validator', () {
    Future<GroupMutedNotificationArtifactValidation> validateKilled(
      GroupKilledTextCardCaptureInput input, {
      Map<String, Object?> Function(Map<String, Object?> artifact)? mutate,
    }) async {
      var artifact = await buildGroupKilledTextCardArtifact(
        proofDirectory: proofDirectory,
        input: input,
      );
      if (mutate != null) artifact = mutate(artifact);
      final artifactFile = File(
        '${proofDirectory.path}${Platform.pathSeparator}'
        '$groupTextKilledAppCardScenarioId.json',
      );
      await artifactFile.writeAsString(jsonEncode(artifact));
      return validateGroupKilledTextCardAndroidArtifact(
        artifactFile: artifactFile,
      );
    }

    test('accepts the killed-app card happy artifact', () async {
      final validation = await validateKilled(
        happyKilledTextCardCaptureInput(),
      );

      expect(validation.ok, isTrue, reason: validation.detail);
    });

    test(
      'rejects an artifact whose graded push has no SHOWN binding',
      () async {
        final validation = await validateKilled(
          missingShownBindingKilledTextCardCaptureInput(),
        );

        expect(validation.ok, isFalse);
        expect(
          validation.detail,
          contains('PUSH_BACKGROUND_NOTIFICATION_SHOWN'),
        );
      },
    );

    test('rejects any PUSH_BACKGROUND_NOTIFICATION_ERROR in the post-kill '
        'window', () async {
      final validation = await validateKilled(
        windowErrorKilledTextCardCaptureInput(),
      );

      expect(validation.ok, isFalse);
      expect(
        validation.detail,
        contains('PUSH_BACKGROUND_NOTIFICATION_ERROR lines in the post-kill'),
      );
    });

    test('rejects an artifact whose graded push is the FIRST post-kill '
        'wake', () async {
      final validation = await validateKilled(
        gradedPushIsFirstWakeCaptureInput(),
      );

      expect(validation.ok, isFalse);
      expect(
        validation.detail,
        contains('the graded push is the FIRST post-kill wake'),
      );
    });

    test(
      'rejects a graded dump that still shows only the warm-up card',
      () async {
        final validation = await validateKilled(
          staleCardKilledTextCardCaptureInput(),
        );

        expect(validation.ok, isFalse);
        expect(validation.detail, contains('carrying the graded marker'));
      },
    );

    test('rejects a missing pre-kill alive-lane baseline card', () async {
      final happy = happyKilledTextCardCaptureInput();
      final validation = await validateKilled(
        happy.copyWith(
          card: happy.card.copyWith(
            preKillNotificationDump: mutedNotificationDumpFixture(
              packageName: 'com.mknoon.app',
              controlGroupName: null,
              controlMarker: null,
            ),
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('alive-lane control'));
    });

    test('rejects a summary claiming a graded card while the raw dump has '
        'none', () async {
      final happy = happyKilledTextCardCaptureInput();
      // Summary still says one graded card; the raw dump holds none. The
      // count rule alone would pass this — only re-deriving from the raw
      // capture catches it.
      final validation = await validateKilled(
        happy.copyWith(
          card: happy.card.copyWith(
            gradedNotificationDump: mutedNotificationDumpFixture(
              packageName: 'com.mknoon.app',
              controlGroupName: null,
              controlMarker: null,
            ),
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('carrying the graded marker'));
    });

    test('rejects a recipient that was never terminated', () async {
      final happy = happyKilledTextCardCaptureInput();
      final validation = await validateKilled(
        happy.copyWith(
          delivery: happy.delivery.copyWith(
            recipientProcessState: 'backgrounded',
          ),
        ),
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('must be terminated'));
    });

    test(
      'the killed-card artifact is rejected by the muted validator',
      () async {
        final artifactFile = File(
          '${proofDirectory.path}${Platform.pathSeparator}'
          '$groupTextKilledAppCardScenarioId.json',
        );
        await writeGroupKilledTextCardArtifact(
          proofDirectory: proofDirectory,
          input: happyKilledTextCardCaptureInput(),
        );

        final crossed = await validateGroupMutedNotificationAndroidArtifact(
          artifactFile: artifactFile,
        );

        expect(
          crossed.ok,
          isFalse,
          reason:
              'the muted grammar asserts the ABSENCE of the card this '
              'scenario proves present; it must never accept this artifact',
        );
      },
    );
  });

  group('Plan 384 killed-text-card push binding', () {
    String log({required List<String> received, required List<String> shown}) =>
        killedTextCardFlowLogFixture(
          receivedFcmMessageIds: received,
          shownFcmMessageIds: shown,
        );

    test('binds the graded push and never the warm-up wake', () {
      final binding = resolveKilledTextCardPushBinding(
        log(
          received: <String>['warm', 'graded'],
          shown: <String>['warm', 'graded'],
        ),
      );

      expect(binding, isNotNull);
      expect(binding!.warmupFcmMessageId, 'warm');
      expect(binding.gradedFcmMessageId, 'graded');
    });

    test('fails closed when only the warm-up wake is recorded', () {
      expect(
        resolveKilledTextCardPushBinding(
          log(received: <String>['warm'], shown: <String>['warm']),
        ),
        isNull,
      );
    });

    test('fails closed when nothing beyond the warm-up was presented', () {
      expect(
        resolveKilledTextCardPushBinding(
          log(received: <String>['warm', 'graded'], shown: <String>['warm']),
        ),
        isNull,
      );
    });
  });

  group('Plan 379 out-of-catalog registration', () {
    test('muted ids resolve via lookup and stay out of the catalog', () {
      for (final id in const <String>[
        groupMutedMessageSuppressionScenarioId,
        groupMutedReactionBackgroundScenarioId,
        groupTextKilledAppCardScenarioId,
      ]) {
        final scenario = groupReactionNotificationScenario(id);
        expect(scenario, isNotNull, reason: '$id must resolve out-of-catalog');
        expect(scenario!.id, id);
        expect(scenario.recipientPlatform, 'android');
        expect(
          scenario.evidenceRequirements,
          isEmpty,
          reason: '$id must not inherit the Plan 257 evidence grammar',
        );
      }

      expect(groupReactionNotificationScenarios, hasLength(6));
      expect(
        groupReactionNotificationScenarios.map((scenario) => scenario.id),
        isNot(contains(groupMutedMessageSuppressionScenarioId)),
      );
      expect(
        groupReactionNotificationScenarios.map((scenario) => scenario.id),
        isNot(contains(groupMutedReactionBackgroundScenarioId)),
      );
      expect(
        groupReactionNotificationScenarios.map((scenario) => scenario.id),
        isNot(contains(groupTextKilledAppCardScenarioId)),
      );
    });

    test('muted id consts match their shared source scenarios', () {
      expect(
        groupMutedMessageSuppressionScenarioId,
        groupMutedMessageSuppressionSourceScenario.id,
      );
      expect(
        groupMutedReactionBackgroundScenarioId,
        groupMutedReactionBackgroundSourceScenario.id,
      );
      expect(
        groupTextKilledAppCardScenarioId,
        groupTextKilledAppCardSourceScenario.id,
      );
    });

    test('the lane census carries all three ids with 384 LAST', () {
      expect(groupMutedNotificationScenarioIds, <String>[
        groupMutedMessageSuppressionScenarioId,
        groupMutedReactionBackgroundScenarioId,
        groupTextKilledAppCardScenarioId,
      ]);
    });

    test('no lane id is a prefix of another', () {
      for (final outer in groupMutedNotificationScenarioIds) {
        for (final inner in groupMutedNotificationScenarioIds) {
          if (outer == inner) continue;
          expect(
            inner.startsWith(outer),
            isFalse,
            reason:
                '$outer is a prefix of $inner; the anchored --name '
                'selector cannot separate them',
          );
        }
      }
    });

    test('no lane id carries the message-lifecycle suffix', () {
      for (final id in const <String>[
        groupMutedMessageSuppressionScenarioId,
        groupMutedReactionBackgroundScenarioId,
        groupTextKilledAppCardScenarioId,
      ]) {
        expect(id.endsWith('_message_unread_lifecycle'), isFalse);
      }
    });
  });

  group('Plan 379 Group Info mute-row targeting', () {
    // Derived from a REAL Pixel 6 capture (2026-08-17,
    // `*_diagnostic_group_info_mute_row_not_found.xml`). The important facts
    // this fixture preserves, which an invented tree got wrong:
    //   * every `text=` attribute is EMPTY — plain `Text` widgets, including
    //     "Mute Notifications" and its subtitle, are absent from the tree;
    //   * only explicit `Semantics` labels appear, as `content-desc`;
    //   * the switch carries `NAF="true"` (no accessible label) but does
    //     expose `checkable`/`checked`.
    String groupInfoDump({required bool muted, bool secondSwitch = false}) {
      final nodes = <String>[
        '<node index="0" text="" resource-id="" class="android.widget.FrameLayout" '
            'package="com.mknoon.app" content-desc="" checkable="false" checked="false" '
            'clickable="false" enabled="true" focusable="false" bounds="[0,0][1080,2400]" />',
        '<node index="0" text="" resource-id="" class="android.widget.Button" '
            'package="com.mknoon.app" content-desc="" checkable="false" checked="false" '
            'clickable="true" enabled="true" focusable="true" bounds="[11,149][137,275]" />',
        '<node index="1" text="" resource-id="" class="android.view.View" '
            'package="com.mknoon.app" content-desc="Group Info" checkable="false" '
            'checked="false" clickable="false" enabled="true" focusable="true" '
            'bounds="[147,174][402,250]" />',
        '<node index="2" text="" resource-id="" class="android.view.View" '
            'package="com.mknoon.app" content-desc="Shared media" checkable="false" '
            'checked="false" clickable="true" enabled="true" focusable="true" '
            'bounds="[64,420][1016,540]" />',
        '<node NAF="true" index="1" text="" resource-id="" class="android.widget.Switch" '
            'package="com.mknoon.app" content-desc="" checkable="true" '
            'checked="${muted ? 'true' : 'false'}" clickable="true" enabled="true" '
            'focusable="true" bounds="[837,647][995,773]" />',
        if (secondSwitch)
          '<node NAF="true" index="2" text="" resource-id="" class="android.widget.Switch" '
              'package="com.mknoon.app" content-desc="" checkable="true" checked="false" '
              'clickable="true" enabled="true" focusable="true" bounds="[837,1200][995,1326]" />',
        '<node index="3" text="" resource-id="" class="android.view.View" '
            'package="com.mknoon.app" content-desc="Leave Group" checkable="false" '
            'checked="false" clickable="true" enabled="true" focusable="true" '
            'bounds="[64,1900][1016,2020]" />',
      ];
      return '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'
          '<hierarchy rotation="0">${nodes.join()}</hierarchy>';
    }

    test('detects Group Info by its app-bar label, not the mute row', () {
      expect(isGroupInfoSurface(groupInfoDump(muted: false)), isTrue);
      expect(isGroupInfoSurface('<hierarchy />'), isFalse);
    });

    test('does not depend on the unexposed mute label', () {
      // Regression guard: the real tree has no "Mute Notifications" node, so
      // any helper keyed on it can never fire on device.
      expect(groupInfoDump(muted: false), isNot(contains(groupMuteRowLabel)));
      expect(findGroupMuteSwitchCenter(groupInfoDump(muted: false)), isNotNull);
    });

    test('locates the unique mute switch by its own bounds', () {
      expect(findGroupMuteSwitchCenter(groupInfoDump(muted: false)), (
        916,
        710,
      ));
    });

    test('reads mute state from the switch checked attribute', () {
      expect(groupMuteSwitchChecked(groupInfoDump(muted: true)), isTrue);
      expect(groupMuteSwitchChecked(groupInfoDump(muted: false)), isFalse);
      expect(groupMuteSwitchChecked('<hierarchy />'), isNull);
    });

    test('fails closed when the switch is ambiguous or absent', () {
      // A second switch must NOT be silently mis-tapped.
      expect(
        findGroupMuteSwitchCenter(
          groupInfoDump(muted: false, secondSwitch: true),
        ),
        isNull,
      );
      expect(findGroupMuteSwitchCenter('<hierarchy />'), isNull);
    });

    test('still uses the row band when a label IS exposed', () {
      const labelled =
          '<hierarchy>'
          '<node class="android.widget.TextView" text="Mute Notifications" '
          'content-desc="" checkable="false" checked="false" clickable="false" '
          'bounds="[104,900][700,948]" />'
          '<node class="android.widget.Switch" text="" content-desc="" '
          'checkable="true" checked="false" clickable="true" bounds="[900,912][1020,984]" />'
          '<node class="android.widget.Switch" text="" content-desc="" '
          'checkable="true" checked="false" clickable="true" bounds="[900,1400][1020,1472]" />'
          '</hierarchy>';

      expect(findGroupMuteSwitchCenter(labelled), (960, 948));
    });

    test('picks the rightmost header button as the info control', () {
      // This one was already correct on device: the tap landed at (996,212).
      expect(findGroupInfoEntryCenter(groupInfoDump(muted: false)), (74, 212));
    });

    test('returns null when no unlabeled header button exists', () {
      expect(findGroupInfoEntryCenter('<hierarchy />'), isNull);
    });
  });

  group('Plan 379 capture dispatch', () {
    test('capture dispatch routes every registered scenario id', () {
      const expected =
          <
            String,
            (
              GroupReactionCaptureLifecycleStage,
              GroupReactionCaptureObservationKind,
              GroupReactionCaptureValidatorKind,
            )
          >{
            'android_group_message_unread_lifecycle': (
              GroupReactionCaptureLifecycleStage.messageUnreadLifecycle,
              GroupReactionCaptureObservationKind.messageMarkers,
              GroupReactionCaptureValidatorKind.reaction,
            ),
            'android_announcement_message_unread_lifecycle': (
              GroupReactionCaptureLifecycleStage.messageUnreadLifecycle,
              GroupReactionCaptureObservationKind.messageMarkers,
              GroupReactionCaptureValidatorKind.reaction,
            ),
            'android_group_reaction_recipient': (
              GroupReactionCaptureLifecycleStage.reactionRecipient,
              GroupReactionCaptureObservationKind.reactionTarget,
              GroupReactionCaptureValidatorKind.reaction,
            ),
            'android_announcement_reaction_recipient': (
              GroupReactionCaptureLifecycleStage.reactionRecipient,
              GroupReactionCaptureObservationKind.reactionTarget,
              GroupReactionCaptureValidatorKind.reaction,
            ),
            'android_group_reaction_recipient_background_connected': (
              GroupReactionCaptureLifecycleStage.reactionRecipient,
              GroupReactionCaptureObservationKind.reactionTarget,
              GroupReactionCaptureValidatorKind.reaction,
            ),
            'ios_announcement_reaction_recipient': (
              GroupReactionCaptureLifecycleStage.reactionRecipient,
              GroupReactionCaptureObservationKind.reactionTarget,
              GroupReactionCaptureValidatorKind.reaction,
            ),
            'android_group_notification_projection_durability': (
              GroupReactionCaptureLifecycleStage.notificationProjection,
              GroupReactionCaptureObservationKind.reactionTarget,
              GroupReactionCaptureValidatorKind.notificationProjection,
            ),
            'android_group_muted_message_suppression': (
              GroupReactionCaptureLifecycleStage.mutedMessageSuppression,
              GroupReactionCaptureObservationKind.mutedTarget,
              GroupReactionCaptureValidatorKind.muted,
            ),
            'android_group_muted_reaction_background_suppression': (
              GroupReactionCaptureLifecycleStage
                  .mutedReactionBackgroundSuppression,
              GroupReactionCaptureObservationKind.mutedTarget,
              GroupReactionCaptureValidatorKind.muted,
            ),
            'android_group_text_killed_app_card': (
              GroupReactionCaptureLifecycleStage.groupTextKilledAppCard,
              GroupReactionCaptureObservationKind.mutedTarget,
              GroupReactionCaptureValidatorKind.killedTextCard,
            ),
          };

      for (final entry in expected.entries) {
        final dispatch = groupReactionCaptureDispatchFor(entry.key);
        expect(dispatch, isNotNull, reason: '${entry.key} must dispatch');
        expect(
          dispatch!.lifecycleStage,
          entry.value.$1,
          reason: '${entry.key} lifecycle stage',
        );
        expect(
          dispatch.observationKind,
          entry.value.$2,
          reason: '${entry.key} observation kind',
        );
        expect(
          dispatch.validatorKind,
          entry.value.$3,
          reason: '${entry.key} validator kind',
        );
      }
    });

    test('capture dispatch covers every registered scenario id', () {
      final registered = <String>[
        ...groupReactionNotificationScenarios.map((scenario) => scenario.id),
        groupNotificationProjectionAndroidSourceScenario.id,
        ...groupMutedNotificationScenarioIds,
      ];

      for (final id in registered) {
        expect(
          groupReactionCaptureDispatchFor(id),
          isNotNull,
          reason: '$id has no capture dispatch',
        );
      }
    });

    test('capture dispatch returns null for an unregistered id', () {
      expect(groupReactionCaptureDispatchFor('android_not_a_scenario'), isNull);
      expect(groupReactionCaptureDispatchFor(''), isNull);
    });

    test('only the muted ids select the muted validator', () {
      final registered = <String>[
        ...groupReactionNotificationScenarios.map((scenario) => scenario.id),
        groupNotificationProjectionAndroidSourceScenario.id,
        ...groupMutedNotificationScenarioIds,
      ];
      final muted = registered.where(
        (id) =>
            groupReactionCaptureDispatchFor(id)!.validatorKind ==
            GroupReactionCaptureValidatorKind.muted,
      );

      expect(muted, <String>[
        groupMutedMessageSuppressionScenarioId,
        groupMutedReactionBackgroundScenarioId,
      ]);

      // The killed-card scenario must NOT ride the muted grammar: its
      // validator asserts a card is present where the muted one asserts the
      // absence of exactly that card.
      final killed = registered.where(
        (id) =>
            groupReactionCaptureDispatchFor(id)!.validatorKind ==
            GroupReactionCaptureValidatorKind.killedTextCard,
      );

      expect(killed, <String>[groupTextKilledAppCardScenarioId]);
    });
  });
}
