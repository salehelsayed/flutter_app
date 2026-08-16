import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('notification-final-effect-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test(
    'TC-372-03 final visibility barrier chooses exactly one in-chat or OS-posted effect',
    () async {
      for (final producer in LocalNotificationProducerKind.values) {
        final isGroup =
            producer == LocalNotificationProducerKind.groupMessage ||
            producer == LocalNotificationProducerKind.groupReaction;
        final conversationKey = isGroup
            ? 'group:${producer.wireName}'
            : 'peer-${producer.wireName}';
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: isGroup
              ? AppVisibilityConversationLane.group
              : AppVisibilityConversationLane.direct,
          value: conversationKey,
        )!;

        for (final finalSameChat in <bool>[false, true]) {
          final directory = Directory(
            '${root.path}/${producer.wireName}-$finalSameChat',
          );
          final fixture = await _Fixture.open(directory, conversationKey);
          final log = <String>[];
          final visibility = _MutableVisibility(
            evaluation: _foregroundEvaluation(maySuppress: !finalSameChat),
            log: log,
          );

          // This is the preparatory/early answer. The canonical barrier then
          // flips lifecycle before the coordinator performs its last read.
          await visibility.evaluate(identity);
          final context = _context(
            label: '${producer.wireName}-$finalSameChat',
            identity: identity,
            producer: producer,
            readFinal: () async {
              log.add('canonical');
              visibility.evaluation = finalSameChat
                  ? _foregroundEvaluation(maySuppress: true)
                  : _backgroundEvaluation();
              return DurableLocalNotificationCanonicalDisposition.eligible;
            },
          );
          await fixture.initialize(context.currentOpaqueBinding);
          var nativeEffects = 0;

          final result = await fixture.registry.runFinalEffect(
            context: context,
            appVisibility: visibility,
            conversationIdentity: identity,
            conversationKey: conversationKey,
            notificationId: fixture.notificationId,
            metadata: ConversationNotificationContentMetadata(
              kind:
                  producer == LocalNotificationProducerKind.directReaction ||
                      producer == LocalNotificationProducerKind.groupReaction
                  ? ConversationNotificationContentKind.reaction
                  : ConversationNotificationContentKind.message,
              eventIdentity: context.eventCorrelation,
              generation: 'generation-${producer.wireName}-$finalSameChat',
            ),
            retireCurrent: () async => log.add('retire'),
            publishNative: () async {
              log.add('native');
              nativeEffects += 1;
            },
          );

          expect(
            result.disposition,
            finalSameChat
                ? DurableLocalNotificationEffectDisposition.inChat
                : DurableLocalNotificationEffectDisposition.osPosted,
            reason: producer.wireName,
          );
          expect(
            result.currentNativeEntryAttempted,
            !finalSameChat,
            reason: 'only this attempt\'s native callback is marked entered',
          );
          expect(nativeEffects, finalSameChat ? 0 : 1);
          expect(
            log.where((entry) => entry == 'visibility').length,
            2,
            reason: 'one preparatory and one final visibility read',
          );
          if (!finalSameChat) {
            expect(log.sublist(log.length - 2), <String>[
              'visibility',
              'native',
            ]);
          }

          final record = await fixture.record(
            binding: context.currentOpaqueBinding,
            correlation: context.eventCorrelation,
          );
          expect(
            record.effectPhase,
            LocalNotificationEffectPhase.effectTerminal,
          );
          expect(
            record.presentationState,
            finalSameChat
                ? LocalNotificationPresentationState.inChat
                : LocalNotificationPresentationState.osPosted,
          );
          expect(record.settledAtUtc, isNull);
          expect(
            record.lastEvaluatedLifecycle,
            finalSameChat
                ? LocalNotificationEvaluatedLifecycle.foregroundActive
                : LocalNotificationEvaluatedLifecycle.background,
          );
          expect(
            await fixture.registry.lookupExactEffect(
              currentOpaqueBinding: context.currentOpaqueBinding,
              eventCorrelation: context.eventCorrelation,
              conversationDigest: context.conversationDigest,
              notificationId: fixture.notificationId,
              contentGeneration:
                  'generation-${producer.wireName}-$finalSameChat',
            ),
            isNotNull,
          );
          expect(
            await fixture.registry.lookupExactEffect(
              currentOpaqueBinding: context.currentOpaqueBinding,
              eventCorrelation: context.eventCorrelation,
              conversationDigest: context.conversationDigest,
              notificationId: fixture.notificationId,
              contentGeneration: 'generation-newer',
            ),
            isNull,
          );

          final replay = await fixture.registry.runFinalEffect(
            context: context,
            appVisibility: visibility,
            conversationIdentity: identity,
            conversationKey: conversationKey,
            notificationId: fixture.notificationId,
            metadata: ConversationNotificationContentMetadata(
              kind:
                  producer == LocalNotificationProducerKind.directReaction ||
                      producer == LocalNotificationProducerKind.groupReaction
                  ? ConversationNotificationContentKind.reaction
                  : ConversationNotificationContentKind.message,
              eventIdentity: context.eventCorrelation,
              generation: 'generation-${producer.wireName}-$finalSameChat',
            ),
            retireCurrent: () async => fail('terminal replay must not retire'),
            publishNative: () async => fail('terminal replay must not publish'),
          );
          expect(replay.disposition, result.disposition);
          expect(replay.currentNativeEntryAttempted, isFalse);
          expect(
            replay.receipt?.recordRevision,
            result.receipt?.recordRevision,
          );

          final mismatchedGeneration = await fixture.registry.runFinalEffect(
            context: context,
            appVisibility: visibility,
            conversationIdentity: identity,
            conversationKey: conversationKey,
            notificationId: fixture.notificationId,
            metadata: ConversationNotificationContentMetadata(
              kind:
                  producer == LocalNotificationProducerKind.directReaction ||
                      producer == LocalNotificationProducerKind.groupReaction
                  ? ConversationNotificationContentKind.reaction
                  : ConversationNotificationContentKind.message,
              eventIdentity: context.eventCorrelation,
              generation: 'generation-mismatch',
            ),
            retireCurrent: () async =>
                fail('mismatched terminal generation must not retire'),
            publishNative: () async =>
                fail('mismatched terminal generation must not publish'),
          );
          expect(
            mismatchedGeneration.disposition,
            DurableLocalNotificationEffectDisposition.retryable,
          );
          expect(mismatchedGeneration.receipt, isNull);
        }
      }
    },
  );

  test(
    'final-effect supporting canonical CAS prevents stale generation mutation',
    () async {
      final cancelledDirectory = Directory('${root.path}/cancelled');
      final cancelledFixture = await _Fixture.open(
        cancelledDirectory,
        'peer-cancelled',
      );
      final cancelledIdentity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-cancelled',
      )!;
      final cancelledContext = _context(
        label: 'cancelled',
        identity: cancelledIdentity,
        producer: LocalNotificationProducerKind.directMessage,
        readFinal: () async =>
            DurableLocalNotificationCanonicalDisposition.read,
      );
      await cancelledFixture.initialize(cancelledContext.currentOpaqueBinding);
      var cancelledNativeEffects = 0;

      final cancelled = await cancelledFixture.registry.runFinalEffect(
        context: cancelledContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: cancelledIdentity,
        conversationKey: 'peer-cancelled',
        notificationId: cancelledFixture.notificationId,
        metadata: ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: cancelledContext.eventCorrelation,
          generation: 'generation-cancelled',
        ),
        retireCurrent: () async {},
        publishNative: () async => cancelledNativeEffects += 1,
      );

      expect(
        cancelled.disposition,
        DurableLocalNotificationEffectDisposition.cancelled,
      );
      expect(cancelledNativeEffects, 0);
      expect(
        (await cancelledFixture.record(
          binding: cancelledContext.currentOpaqueBinding,
          correlation: cancelledContext.eventCorrelation,
        )).readState,
        LocalNotificationReadState.read,
      );
      expect(
        await cancelledFixture.registry.settleSqlReadyEffect(
          currentOpaqueBinding: cancelledContext.currentOpaqueBinding,
          eventCorrelation: cancelledContext.eventCorrelation,
          expectedRevision: cancelled.receipt!.recordRevision - 1,
        ),
        isNull,
      );
      final settled = await cancelledFixture.registry.settleSqlReadyEffect(
        currentOpaqueBinding: cancelledContext.currentOpaqueBinding,
        eventCorrelation: cancelledContext.eventCorrelation,
        expectedRevision: cancelled.receipt!.recordRevision,
      );
      expect(settled?.effectPhase, LocalNotificationEffectPhase.settled);
      expect(
        await cancelledFixture.registry.settleSqlReadyEffect(
          currentOpaqueBinding: cancelledContext.currentOpaqueBinding,
          eventCorrelation: cancelledContext.eventCorrelation,
          expectedRevision: cancelled.receipt!.recordRevision,
        ),
        isNotNull,
        reason: 'a lost settlement response must replay idempotently',
      );
      final settledReplay = await cancelledFixture.registry.runFinalEffect(
        context: cancelledContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: cancelledIdentity,
        conversationKey: 'peer-cancelled',
        notificationId: cancelledFixture.notificationId,
        metadata: ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: cancelledContext.eventCorrelation,
          generation: 'generation-cancelled',
        ),
        retireCurrent: () async => fail('SETTLED replay must not retire'),
        publishNative: () async => fail('SETTLED replay must not publish'),
      );
      expect(
        settledReplay.receipt?.recordRevision,
        cancelled.receipt!.recordRevision,
      );
      expect(
        await cancelledFixture.registry.settleSqlReadyEffect(
          currentOpaqueBinding: cancelledContext.currentOpaqueBinding,
          eventCorrelation: cancelledContext.eventCorrelation,
          expectedRevision: settledReplay.receipt!.recordRevision,
        ),
        isNotNull,
        reason: 'fresh SETTLED replay must preserve terminal receipt semantics',
      );

      final racedDirectory = Directory('${root.path}/generation-race');
      final racedFixture = await _Fixture.open(
        racedDirectory,
        'group:generation-race',
      );
      final racedIdentity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.group,
        value: 'group:generation-race',
      )!;
      const laterMetadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.reaction,
        eventIdentity: 'later-event',
        generation: 'generation-later',
      );
      late final DurableLocalNotificationEffectContext racedContext;
      racedContext = _context(
        label: 'generation-race',
        identity: racedIdentity,
        producer: LocalNotificationProducerKind.groupMessage,
        readFinal: () async {
          // A second owner wins after PUBLISHING. The exact marker reread must
          // prevent the stale event from showing or deleting this generation.
          await File(
            '${racedDirectory.path}/${racedFixture.notificationId}'
            '${DurableConversationNotificationIdRegistry.contentKindFileSuffix}',
          ).writeAsString(jsonEncode(laterMetadata.toJson()), flush: true);
          return DurableLocalNotificationCanonicalDisposition.eligible;
        },
      );
      await racedFixture.initialize(racedContext.currentOpaqueBinding);
      var racedNativeEffects = 0;

      final raced = await racedFixture.registry.runFinalEffect(
        context: racedContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: racedIdentity,
        conversationKey: 'group:generation-race',
        notificationId: racedFixture.notificationId,
        metadata: ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: racedContext.eventCorrelation,
          generation: 'generation-stale',
        ),
        retireCurrent: () async {},
        publishNative: () async => racedNativeEffects += 1,
      );

      expect(
        raced.disposition,
        DurableLocalNotificationEffectDisposition.retryable,
      );
      expect(racedNativeEffects, 0);
      expect(
        await racedFixture.registry.lookupContentMetadata(
          conversationKey: 'group:generation-race',
          notificationId: racedFixture.notificationId,
        ),
        laterMetadata,
      );
      final racedRecord = await racedFixture.record(
        binding: racedContext.currentOpaqueBinding,
        correlation: racedContext.eventCorrelation,
      );
      expect(racedRecord.effectPhase, LocalNotificationEffectPhase.publishing);
      expect(
        racedRecord.presentationState,
        LocalNotificationPresentationState.notEvaluated,
      );
    },
  );

  test('relay custody upgrade is phase-preserving and idempotent', () async {
    final directory = Directory('${root.path}/relay-upgrade');
    final fixture = await _Fixture.open(directory, 'peer-relay-upgrade');
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.direct,
      value: 'peer-relay-upgrade',
    )!;
    final context = _context(
      label: 'relay-upgrade',
      identity: identity,
      producer: LocalNotificationProducerKind.directMessage,
      sourceCustody: LocalNotificationSourceCustody.relayVerifiedUnacked,
      presentationOwner: LocalNotificationPresentationOwner.iosNse,
      readFinal: () async =>
          DurableLocalNotificationCanonicalDisposition.eligible,
    );
    await fixture.initialize(context.currentOpaqueBinding);
    final terminal = await fixture.registry.runFinalEffect(
      context: context,
      appVisibility: _MutableVisibility(
        evaluation: _foregroundEvaluation(maySuppress: true),
        log: <String>[],
      ),
      conversationIdentity: identity,
      conversationKey: 'peer-relay-upgrade',
      notificationId: fixture.notificationId,
      metadata: ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: context.eventCorrelation,
        generation: 'generation-relay-upgrade',
      ),
      retireCurrent: () async {},
      publishNative: () async => fail('same-chat relay must not publish'),
    );
    expect(
      terminal.disposition,
      DurableLocalNotificationEffectDisposition.inChat,
    );

    final sqlContext = DurableLocalNotificationEffectContext(
      currentOpaqueBinding: context.currentOpaqueBinding,
      eventCorrelation: context.eventCorrelation,
      conversationDigest: context.conversationDigest,
      producerKind: context.producerKind,
      sourceCustody: LocalNotificationSourceCustody.sqlReady,
      presentationOwner: LocalNotificationPresentationOwner.mainApp,
      readFinalCanonicalDisposition: () async =>
          DurableLocalNotificationCanonicalDisposition.eligible,
    );
    final reopenedRegistry = DurableConversationNotificationIdRegistry(
      directory: directory,
      localNotificationEffectCoordinator:
          DurableLocalNotificationEffectCoordinator(
            ledgerStore: LocalNotificationLedgerStore(directory: directory),
            nowUtc: () => DateTime.utc(2026, 8, 16, 12, 1),
            effectTokenFactory: () => 'e' * 64,
          ),
    );
    final adopted = await reopenedRegistry.runFinalEffect(
      context: sqlContext,
      appVisibility: _MutableVisibility(
        evaluation: _foregroundEvaluation(maySuppress: true),
        log: <String>[],
      ),
      conversationIdentity: identity,
      conversationKey: 'peer-relay-upgrade',
      notificationId: fixture.notificationId,
      metadata: ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: context.eventCorrelation,
        generation: 'generation-relay-upgrade',
      ),
      retireCurrent: () async => fail('terminal adoption must not retire'),
      publishNative: () async => fail('terminal adoption must not publish'),
    );
    expect(adopted.disposition, terminal.disposition);
    expect(
      adopted.receipt?.recordRevision,
      terminal.receipt!.recordRevision + 1,
    );
    final listed = await reopenedRegistry.listSqlReadyEffectTerminals(
      currentOpaqueBinding: context.currentOpaqueBinding,
    );
    expect(listed, hasLength(1));
    expect(listed.single.eventCorrelation, context.eventCorrelation);
    expect(
      listed.single.presentationOwner,
      LocalNotificationPresentationOwner.iosNse,
      reason: 'SQL materialization must preserve the native effect owner',
    );
    await expectLater(
      reopenedRegistry.listSqlReadyEffectTerminals(
        currentOpaqueBinding: 'v1:${_digest('wrong-binding')}',
      ),
      throwsStateError,
    );

    final upgraded = await reopenedRegistry.upgradeRelayCustodyToSqlReady(
      currentOpaqueBinding: context.currentOpaqueBinding,
      eventCorrelation: context.eventCorrelation,
      expectedRevision: terminal.receipt!.recordRevision,
    );
    expect(upgraded?.sourceCustody, LocalNotificationSourceCustody.sqlReady);
    expect(upgraded?.effectPhase, LocalNotificationEffectPhase.effectTerminal);
    expect(
      upgraded?.presentationState,
      LocalNotificationPresentationState.inChat,
    );
    expect(
      await reopenedRegistry.upgradeRelayCustodyToSqlReady(
        currentOpaqueBinding: context.currentOpaqueBinding,
        eventCorrelation: context.eventCorrelation,
        expectedRevision: terminal.receipt!.recordRevision,
      ),
      isNotNull,
    );
    final settled = await reopenedRegistry.settleSqlReadyEffect(
      currentOpaqueBinding: context.currentOpaqueBinding,
      eventCorrelation: context.eventCorrelation,
      expectedRevision: upgraded!.revision,
    );
    expect(settled?.effectPhase, LocalNotificationEffectPhase.settled);
    final awaitingSqlRetirement = await reopenedRegistry
        .listSqlReadyEffectTerminals(
          currentOpaqueBinding: context.currentOpaqueBinding,
        );
    expect(awaitingSqlRetirement, hasLength(1));
    expect(
      awaitingSqlRetirement.single.effectPhase,
      LocalNotificationEffectPhase.settled,
      reason: 'post-settle/pre-SQL-B cuts retain a recovery owner',
    );
  });

  test(
    'materialized relay READY and aged CLAIMED continue under the native owner',
    () async {
      Future<
        ({
          _Fixture fixture,
          AppVisibilityConversationIdentity identity,
          DurableLocalNotificationEffectContext sqlContext,
          ConversationNotificationContentMetadata metadata,
        })
      >
      seed({
        required String label,
        required LocalNotificationEffectPhase phase,
        required DateTime updatedAt,
        required DateTime Function() nowUtc,
      }) async {
        final conversationKey = 'peer-$label';
        final directory = Directory('${root.path}/$label');
        final fixture = await _Fixture.open(
          directory,
          conversationKey,
          nowUtc: nowUtc,
        );
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.direct,
          value: conversationKey,
        )!;
        final relayContext = _context(
          label: label,
          identity: identity,
          producer: LocalNotificationProducerKind.directMessage,
          sourceCustody: LocalNotificationSourceCustody.relayVerifiedUnacked,
          presentationOwner:
              LocalNotificationPresentationOwner.androidPushService,
          readFinal: () async =>
              DurableLocalNotificationCanonicalDisposition.eligible,
        );
        final sqlContext = DurableLocalNotificationEffectContext(
          currentOpaqueBinding: relayContext.currentOpaqueBinding,
          eventCorrelation: relayContext.eventCorrelation,
          conversationDigest: relayContext.conversationDigest,
          producerKind: relayContext.producerKind,
          sourceCustody: LocalNotificationSourceCustody.sqlReady,
          presentationOwner: LocalNotificationPresentationOwner.mainApp,
          readFinalCanonicalDisposition:
              relayContext.readFinalCanonicalDisposition,
        );
        await fixture.initialize(relayContext.currentOpaqueBinding);
        final generation = 'generation-$label';
        final record = LocalNotificationRecordV1(
          eventCorrelation: relayContext.eventCorrelation,
          conversationDigest: relayContext.conversationDigest,
          producerKind: relayContext.producerKind,
          sourceCustody: LocalNotificationSourceCustody.relayVerifiedUnacked,
          readState: LocalNotificationReadState.unread,
          presentationState: LocalNotificationPresentationState.notEvaluated,
          presentationOwner:
              LocalNotificationPresentationOwner.androidPushService,
          notificationId: fixture.notificationId,
          contentGeneration: generation,
          lastEvaluatedLifecycle: LocalNotificationEvaluatedLifecycle.unknown,
          visibilityRevision: null,
          lifecycleGeneration: null,
          effectPhase: phase,
          attemptKind: phase == LocalNotificationEffectPhase.claimed
              ? LocalNotificationAttemptKind.postOrUpdate
              : null,
          effectToken: phase == LocalNotificationEffectPhase.claimed
              ? 'c' * 64
              : null,
          revision: phase == LocalNotificationEffectPhase.claimed ? 2 : 1,
          createdAtUtc: updatedAt.toIso8601String(),
          updatedAtUtc: updatedAt.toIso8601String(),
          terminalAtUtc: null,
          settledAtUtc: null,
        );
        expect(record.isValid, isTrue);
        expect(
          await LocalNotificationLedgerStore(directory: directory).mutate(
            currentOpaqueBinding: relayContext.currentOpaqueBinding,
            mutation: (current) => current.copyWith(
              storeRevision: current.storeRevision + 1,
              records: <String, LocalNotificationRecordV1>{
                ...current.records,
                relayContext.eventCorrelation: record,
              },
            ),
          ),
          isNotNull,
        );
        return (
          fixture: fixture,
          identity: identity,
          sqlContext: sqlContext,
          metadata: ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: relayContext.eventCorrelation,
            generation: generation,
          ),
        );
      }

      var readyNow = DateTime.utc(2026, 8, 16, 12, 2);
      final ready = await seed(
        label: 'relay-ready-materialization',
        phase: LocalNotificationEffectPhase.ready,
        updatedAt: DateTime.utc(2026, 8, 16, 12),
        nowUtc: () => readyNow,
      );
      var readyNativeEffects = 0;
      final readyResult = await ready.fixture.registry.runFinalEffect(
        context: ready.sqlContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: ready.identity,
        conversationKey: 'peer-relay-ready-materialization',
        notificationId: ready.fixture.notificationId,
        metadata: ready.metadata,
        retireCurrent: () async {},
        publishNative: () async => readyNativeEffects += 1,
      );
      expect(
        readyResult.disposition,
        DurableLocalNotificationEffectDisposition.osPosted,
      );
      expect(readyNativeEffects, 1);
      final readyRecord = await ready.fixture.record(
        binding: ready.sqlContext.currentOpaqueBinding,
        correlation: ready.sqlContext.eventCorrelation,
      );
      expect(
        readyRecord.sourceCustody,
        LocalNotificationSourceCustody.sqlReady,
      );
      expect(
        readyRecord.presentationOwner,
        LocalNotificationPresentationOwner.androidPushService,
      );

      var claimedNow = DateTime.utc(2026, 8, 16, 12, 0, 59);
      final claimed = await seed(
        label: 'relay-claimed-materialization',
        phase: LocalNotificationEffectPhase.claimed,
        updatedAt: DateTime.utc(2026, 8, 16, 12),
        nowUtc: () => claimedNow,
      );
      var claimedNativeEffects = 0;
      final freshClaim = await claimed.fixture.registry.runFinalEffect(
        context: claimed.sqlContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: claimed.identity,
        conversationKey: 'peer-relay-claimed-materialization',
        notificationId: claimed.fixture.notificationId,
        metadata: claimed.metadata,
        retireCurrent: () async {},
        publishNative: () async => claimedNativeEffects += 1,
      );
      expect(
        freshClaim.disposition,
        DurableLocalNotificationEffectDisposition.retryable,
      );
      expect(claimedNativeEffects, 0);

      claimedNow = claimedNow.add(const Duration(seconds: 1));
      final agedClaim = await claimed.fixture.registry.runFinalEffect(
        context: claimed.sqlContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: claimed.identity,
        conversationKey: 'peer-relay-claimed-materialization',
        notificationId: claimed.fixture.notificationId,
        metadata: claimed.metadata,
        retireCurrent: () async {},
        publishNative: () async => claimedNativeEffects += 1,
      );
      expect(
        agedClaim.disposition,
        DurableLocalNotificationEffectDisposition.osPosted,
      );
      expect(claimedNativeEffects, 1);
      final claimedRecord = await claimed.fixture.record(
        binding: claimed.sqlContext.currentOpaqueBinding,
        correlation: claimed.sqlContext.eventCorrelation,
      );
      expect(
        claimedRecord.presentationOwner,
        LocalNotificationPresentationOwner.androidPushService,
      );
    },
  );

  test(
    'materialized native PUBLISHING uses exact active proof without changing owner or republishing',
    () async {
      final directory = Directory('${root.path}/relay-publishing-recovery');
      final fixture = await _Fixture.open(
        directory,
        'peer-relay-publishing-recovery',
      );
      final identity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-relay-publishing-recovery',
      )!;
      final relayContext = _context(
        label: 'relay-publishing-recovery',
        identity: identity,
        producer: LocalNotificationProducerKind.directMessage,
        sourceCustody: LocalNotificationSourceCustody.relayVerifiedUnacked,
        presentationOwner:
            LocalNotificationPresentationOwner.androidPushService,
        readFinal: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
      await fixture.initialize(relayContext.currentOpaqueBinding);
      final metadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: relayContext.eventCorrelation,
        generation: 'generation-relay-publishing-recovery',
      );
      final ambiguous = await fixture.registry.runFinalEffect(
        context: relayContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-relay-publishing-recovery',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async {},
        publishNative: () async => throw StateError('native outcome unknown'),
      );
      expect(
        ambiguous.disposition,
        DurableLocalNotificationEffectDisposition.ambiguous,
      );

      final sqlContext = DurableLocalNotificationEffectContext(
        currentOpaqueBinding: relayContext.currentOpaqueBinding,
        eventCorrelation: relayContext.eventCorrelation,
        conversationDigest: relayContext.conversationDigest,
        producerKind: relayContext.producerKind,
        sourceCustody: LocalNotificationSourceCustody.sqlReady,
        presentationOwner: LocalNotificationPresentationOwner.mainApp,
        readFinalCanonicalDisposition: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
      final recovered = await fixture.registry.runFinalEffect(
        context: sqlContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-relay-publishing-recovery',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async => fail('active proof must not retire'),
        publishNative: () async => fail('active proof must not republish'),
        activeNotificationIds: () async => <Object?>[fixture.notificationId],
      );
      expect(
        recovered.disposition,
        DurableLocalNotificationEffectDisposition.osPosted,
      );
      expect(recovered.currentNativeEntryAttempted, isFalse);
      final record = await fixture.record(
        binding: relayContext.currentOpaqueBinding,
        correlation: relayContext.eventCorrelation,
      );
      expect(record.sourceCustody, LocalNotificationSourceCustody.sqlReady);
      expect(
        record.presentationOwner,
        LocalNotificationPresentationOwner.androidPushService,
      );
      expect(record.effectPhase, LocalNotificationEffectPhase.effectTerminal);
    },
  );

  test(
    'content activation crash intent is opaque and resumes exact old-card retirement',
    () async {
      var now = DateTime.utc(2026, 8, 16, 12);
      final directory = Directory('${root.path}/activation-intent-recovery');
      final fixture = await _Fixture.open(
        directory,
        'peer-activation-intent-recovery',
        nowUtc: () => now,
      );
      final identity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-activation-intent-recovery',
      )!;
      final context = _context(
        label: 'activation-intent-recovery',
        identity: identity,
        producer: LocalNotificationProducerKind.directMessage,
        readFinal: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
      await fixture.initialize(context.currentOpaqueBinding);
      const rawLegacyEvent = 'raw-legacy-event-must-never-enter-intent';
      await fixture.registry.recordContentMetadata(
        conversationKey: 'peer-activation-intent-recovery',
        notificationId: fixture.notificationId,
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: rawLegacyEvent,
          generation: 'legacy-generation',
        ),
      );
      final metadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: context.eventCorrelation,
        generation: 'generation-activation-intent-recovery',
      );

      var retireCalls = 0;
      final interrupted = await fixture.registry.runFinalEffect(
        context: context,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-activation-intent-recovery',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async {
          retireCalls += 1;
          throw StateError('cut after old-card cancellation entry');
        },
        publishNative: () async => fail('new card must not publish before cut'),
      );
      expect(
        interrupted.disposition,
        DurableLocalNotificationEffectDisposition.ambiguous,
      );
      expect(retireCalls, 1);
      final interruptedRecord = await fixture.record(
        binding: context.currentOpaqueBinding,
        correlation: context.eventCorrelation,
      );
      expect(
        interruptedRecord.attemptKind,
        LocalNotificationAttemptKind.cancel,
      );
      final intent = File(
        '${directory.path}/${fixture.notificationId}'
        '${DurableConversationNotificationIdRegistry.contentActivationIntentFileSuffix}',
      );
      final intentBytes = await intent.readAsString();
      expect(intentBytes, isNot(contains(rawLegacyEvent)));
      expect(intentBytes, isNot(contains(context.eventCorrelation)));
      expect(
        (jsonDecode(intentBytes) as Map<String, Object?>).keys.toSet(),
        <String>{'v', 'opaqueBinding', 'previousDigest', 'nextDigest'},
      );

      now = now.add(const Duration(seconds: 66));
      final reopened = DurableConversationNotificationIdRegistry(
        directory: directory,
        localNotificationEffectCoordinator:
            DurableLocalNotificationEffectCoordinator(
              ledgerStore: LocalNotificationLedgerStore(directory: directory),
              nowUtc: () => now,
              effectTokenFactory: () => 'e' * 64,
            ),
      );
      var silentRepairs = 0;
      final recovered = await reopened.runFinalEffect(
        context: context,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-activation-intent-recovery',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async => retireCalls += 1,
        publishNative: () async => fail('recovery must not alert audibly'),
        publishNativeSilently: () async => silentRepairs += 1,
        activeNotificationIds: () async => const <Object?>[],
      );
      expect(
        recovered.disposition,
        DurableLocalNotificationEffectDisposition.osPosted,
      );
      expect(recovered.currentNativeEntryWasSilentRepair, isTrue);
      expect(retireCalls, 2);
      expect(silentRepairs, 1);
      expect(await intent.exists(), isFalse);
      expect(
        await reopened.lookupContentMetadata(
          conversationKey: 'peer-activation-intent-recovery',
          notificationId: fixture.notificationId,
        ),
        metadata,
      );
    },
  );

  test(
    'a rebound account can replace an old binding activation intent safely',
    () async {
      final directory = Directory('${root.path}/activation-intent-rebind');
      final fixture = await _Fixture.open(
        directory,
        'peer-activation-intent-rebind',
      );
      final identity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-activation-intent-rebind',
      )!;
      final accountA = _context(
        label: 'activation-intent-account-a',
        identity: identity,
        producer: LocalNotificationProducerKind.directMessage,
        readFinal: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
      await fixture.initialize(accountA.currentOpaqueBinding);
      final metadataA = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: accountA.eventCorrelation,
        generation: 'generation-activation-intent-account-a',
      );
      await fixture.registry.runFinalEffect(
        context: accountA,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-activation-intent-rebind',
        notificationId: fixture.notificationId,
        metadata: metadataA,
        retireCurrent: () async => throw StateError('leave account A intent'),
        publishNative: () async => fail('account A must stop before publish'),
      );

      final accountB = _context(
        label: 'activation-intent-account-b',
        identity: identity,
        producer: LocalNotificationProducerKind.directMessage,
        readFinal: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
      expect(
        await LocalNotificationLedgerStore(
          directory: directory,
        ).initializeOrRebind(
          currentOpaqueBinding: accountB.currentOpaqueBinding,
        ),
        isNotNull,
      );
      final metadataB = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: accountB.eventCorrelation,
        generation: 'generation-activation-intent-account-b',
      );
      var nativeEffects = 0;
      final rebound = await fixture.registry.runFinalEffect(
        context: accountB,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-activation-intent-rebind',
        notificationId: fixture.notificationId,
        metadata: metadataB,
        retireCurrent: () async {},
        publishNative: () async => nativeEffects += 1,
      );
      expect(
        rebound.disposition,
        DurableLocalNotificationEffectDisposition.osPosted,
      );
      expect(nativeEffects, 1);
      expect(
        await fixture.registry.lookupContentMetadata(
          conversationKey: 'peer-activation-intent-rebind',
          notificationId: fixture.notificationId,
        ),
        metadataB,
      );
    },
  );

  test(
    'expired CLAIMED resumes only after the incumbent sixty-second horizon',
    () async {
      var now = DateTime.utc(2026, 8, 16, 12);
      final directory = Directory('${root.path}/claimed-recovery');
      final fixture = await _Fixture.open(
        directory,
        'peer-claimed-recovery',
        nowUtc: () => now,
      );
      final identity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-claimed-recovery',
      )!;
      final context = _context(
        label: 'claimed-recovery',
        identity: identity,
        producer: LocalNotificationProducerKind.directMessage,
        readFinal: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
      await fixture.initialize(context.currentOpaqueBinding);
      const generation = 'generation-claimed-recovery';
      final claimed = LocalNotificationRecordV1(
        eventCorrelation: context.eventCorrelation,
        conversationDigest: context.conversationDigest,
        producerKind: context.producerKind,
        sourceCustody: context.sourceCustody,
        readState: LocalNotificationReadState.unread,
        presentationState: LocalNotificationPresentationState.notEvaluated,
        presentationOwner: context.presentationOwner,
        notificationId: fixture.notificationId,
        contentGeneration: generation,
        lastEvaluatedLifecycle: LocalNotificationEvaluatedLifecycle.unknown,
        visibilityRevision: null,
        lifecycleGeneration: null,
        effectPhase: LocalNotificationEffectPhase.claimed,
        attemptKind: LocalNotificationAttemptKind.postOrUpdate,
        effectToken: 'c' * 64,
        revision: 2,
        createdAtUtc: now.toIso8601String(),
        updatedAtUtc: now.toIso8601String(),
        terminalAtUtc: null,
        settledAtUtc: null,
      );
      expect(claimed.isValid, isTrue);
      final store = LocalNotificationLedgerStore(directory: directory);
      expect(
        await store.mutate(
          currentOpaqueBinding: context.currentOpaqueBinding,
          mutation: (current) => current.copyWith(
            storeRevision: current.storeRevision + 1,
            records: <String, LocalNotificationRecordV1>{
              ...current.records,
              context.eventCorrelation: claimed,
            },
          ),
        ),
        isNotNull,
      );
      final metadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: context.eventCorrelation,
        generation: generation,
      );
      var nativeEffects = 0;

      now = now.add(const Duration(seconds: 59));
      final pending = await fixture.registry.runFinalEffect(
        context: context,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-claimed-recovery',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async {},
        publishNative: () async => nativeEffects += 1,
      );
      expect(
        pending.disposition,
        DurableLocalNotificationEffectDisposition.retryable,
      );
      expect(nativeEffects, 0);

      now = now.add(const Duration(seconds: 1));
      final recovered = await fixture.registry.runFinalEffect(
        context: context,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-claimed-recovery',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async {},
        publishNative: () async => nativeEffects += 1,
      );
      expect(
        recovered.disposition,
        DurableLocalNotificationEffectDisposition.osPosted,
      );
      expect(recovered.currentNativeEntryAttempted, isTrue);
      expect(nativeEffects, 1);
    },
  );

  test(
    'native ambiguity retains PUBLISHING while unknown visibility fails toward notification',
    () async {
      final unknownDirectory = Directory('${root.path}/unknown-visibility');
      final unknownFixture = await _Fixture.open(
        unknownDirectory,
        'peer-unknown-visibility',
      );
      final unknownIdentity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-unknown-visibility',
      )!;
      final unknownContext = _context(
        label: 'unknown-visibility',
        identity: unknownIdentity,
        producer: LocalNotificationProducerKind.directMessage,
        readFinal: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
      await unknownFixture.initialize(unknownContext.currentOpaqueBinding);
      var unknownNativeEffects = 0;
      final unknown = await unknownFixture.registry.runFinalEffect(
        context: unknownContext,
        appVisibility: _MutableVisibility(
          evaluation: AppVisibilityEvaluation.failNotify,
          log: <String>[],
        ),
        conversationIdentity: unknownIdentity,
        conversationKey: 'peer-unknown-visibility',
        notificationId: unknownFixture.notificationId,
        metadata: ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: unknownContext.eventCorrelation,
          generation: 'generation-unknown-visibility',
        ),
        retireCurrent: () async {},
        publishNative: () async => unknownNativeEffects += 1,
      );
      expect(
        unknown.disposition,
        DurableLocalNotificationEffectDisposition.osPosted,
      );
      expect(unknownNativeEffects, 1);
      final unknownRecord = await unknownFixture.record(
        binding: unknownContext.currentOpaqueBinding,
        correlation: unknownContext.eventCorrelation,
      );
      expect(
        unknownRecord.lastEvaluatedLifecycle,
        LocalNotificationEvaluatedLifecycle.unknown,
      );
      expect(unknownRecord.visibilityRevision, isNull);
      expect(unknownRecord.lifecycleGeneration, isNull);

      final directory = Directory('${root.path}/native-ambiguity');
      final fixture = await _Fixture.open(directory, 'peer-native-ambiguity');
      final identity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-native-ambiguity',
      )!;
      final context = _context(
        label: 'native-ambiguity',
        identity: identity,
        producer: LocalNotificationProducerKind.directMessage,
        readFinal: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
      await fixture.initialize(context.currentOpaqueBinding);
      final metadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: context.eventCorrelation,
        generation: 'generation-native-ambiguity',
      );

      final result = await fixture.registry.runFinalEffect(
        context: context,
        appVisibility: _MutableVisibility(
          evaluation: AppVisibilityEvaluation.failNotify,
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-native-ambiguity',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async {},
        publishNative: () async => throw StateError('native unknown'),
      );

      expect(
        result.disposition,
        DurableLocalNotificationEffectDisposition.ambiguous,
      );
      expect(result.currentNativeEntryAttempted, isTrue);
      final record = await fixture.record(
        binding: context.currentOpaqueBinding,
        correlation: context.eventCorrelation,
      );
      expect(record.effectPhase, LocalNotificationEffectPhase.publishing);
      expect(record.attemptKind, LocalNotificationAttemptKind.postOrUpdate);
      expect(record.effectToken, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        record.presentationState,
        LocalNotificationPresentationState.notEvaluated,
      );
      expect(
        record.lastEvaluatedLifecycle,
        LocalNotificationEvaluatedLifecycle.unknown,
      );
      expect(
        await fixture.registry.lookupContentMetadata(
          conversationKey: 'peer-native-ambiguity',
          notificationId: fixture.notificationId,
        ),
        metadata,
      );

      var replayNativeCalls = 0;
      final replay = await fixture.registry.runFinalEffect(
        context: context,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-native-ambiguity',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async {},
        publishNative: () async => replayNativeCalls += 1,
      );
      expect(
        replay.disposition,
        DurableLocalNotificationEffectDisposition.ambiguous,
      );
      expect(replay.currentNativeEntryAttempted, isFalse);
      expect(replayNativeCalls, 0);

      final provenActive = await fixture.registry.runFinalEffect(
        context: context,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-native-ambiguity',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async => fail('active proof must not retire'),
        publishNative: () async => fail('active proof must not republish'),
        activeNotificationIds: () async => <Object?>[fixture.notificationId],
      );
      expect(
        provenActive.disposition,
        DurableLocalNotificationEffectDisposition.osPosted,
      );
      expect(provenActive.currentNativeEntryAttempted, isFalse);
    },
  );

  test(
    'PUBLISHING recovery repairs exact absence and bounded inventory failure silently',
    () async {
      var now = DateTime.utc(2026, 8, 16, 12);
      final directory = Directory('${root.path}/publishing-repair');
      final fixture = await _Fixture.open(
        directory,
        'peer-publishing-repair',
        nowUtc: () => now,
      );
      final identity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-publishing-repair',
      )!;
      final context = _context(
        label: 'publishing-repair',
        identity: identity,
        producer: LocalNotificationProducerKind.directMessage,
        readFinal: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
      await fixture.initialize(context.currentOpaqueBinding);
      final metadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: context.eventCorrelation,
        generation: 'generation-publishing-repair',
      );
      await fixture.registry.runFinalEffect(
        context: context,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-publishing-repair',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async {},
        publishNative: () async => throw StateError('ambiguous first call'),
      );

      var repairCalls = 0;
      final absentRepair = await fixture.registry.runFinalEffect(
        context: context,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: identity,
        conversationKey: 'peer-publishing-repair',
        notificationId: fixture.notificationId,
        metadata: metadata,
        retireCurrent: () async {},
        publishNative: () async =>
            fail('recovery must not reuse the ordinary/audible callback'),
        publishNativeSilently: () async => repairCalls += 1,
        activeNotificationIds: () async => const <Object?>[],
      );
      expect(
        absentRepair.disposition,
        DurableLocalNotificationEffectDisposition.osPosted,
      );
      expect(repairCalls, 1);

      final agedDirectory = Directory('${root.path}/publishing-aged-repair');
      final agedFixture = await _Fixture.open(
        agedDirectory,
        'peer-publishing-aged-repair',
        nowUtc: () => now,
      );
      final agedIdentity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-publishing-aged-repair',
      )!;
      final agedContext = _context(
        label: 'publishing-aged-repair',
        identity: agedIdentity,
        producer: LocalNotificationProducerKind.directMessage,
        readFinal: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );
      await agedFixture.initialize(agedContext.currentOpaqueBinding);
      final agedMetadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: agedContext.eventCorrelation,
        generation: 'generation-publishing-aged-repair',
      );
      await agedFixture.registry.runFinalEffect(
        context: agedContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: agedIdentity,
        conversationKey: 'peer-publishing-aged-repair',
        notificationId: agedFixture.notificationId,
        metadata: agedMetadata,
        retireCurrent: () async {},
        publishNative: () async => throw StateError('ambiguous first call'),
      );
      now = now.add(const Duration(seconds: 66));
      var agedRepairCalls = 0;
      final agedRepair = await agedFixture.registry.runFinalEffect(
        context: agedContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: agedIdentity,
        conversationKey: 'peer-publishing-aged-repair',
        notificationId: agedFixture.notificationId,
        metadata: agedMetadata,
        retireCurrent: () async {},
        publishNative: () async =>
            fail('aged recovery must not reuse the audible callback'),
        publishNativeSilently: () async => agedRepairCalls += 1,
        activeNotificationIds: () async => throw StateError('inventory down'),
      );
      expect(
        agedRepair.disposition,
        DurableLocalNotificationEffectDisposition.osPosted,
      );
      expect(agedRepairCalls, 1);

      final cancelDirectory = Directory('${root.path}/publishing-cancel');
      final cancelFixture = await _Fixture.open(
        cancelDirectory,
        'peer-publishing-cancel',
      );
      final cancelIdentity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'peer-publishing-cancel',
      )!;
      var cancelDisposition =
          DurableLocalNotificationCanonicalDisposition.eligible;
      final cancelContext = _context(
        label: 'publishing-cancel',
        identity: cancelIdentity,
        producer: LocalNotificationProducerKind.directMessage,
        readFinal: () async => cancelDisposition,
      );
      await cancelFixture.initialize(cancelContext.currentOpaqueBinding);
      final cancelMetadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: cancelContext.eventCorrelation,
        generation: 'generation-publishing-cancel',
      );
      await cancelFixture.registry.runFinalEffect(
        context: cancelContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: <String>[],
        ),
        conversationIdentity: cancelIdentity,
        conversationKey: 'peer-publishing-cancel',
        notificationId: cancelFixture.notificationId,
        metadata: cancelMetadata,
        retireCurrent: () async {},
        publishNative: () async => throw StateError('ambiguous first call'),
      );
      cancelDisposition =
          DurableLocalNotificationCanonicalDisposition.cancelled;
      final cancelOrder = <String>[];
      var cancelCalls = 0;
      final cancelled = await cancelFixture.registry.runFinalEffect(
        context: cancelContext,
        appVisibility: _MutableVisibility(
          evaluation: _backgroundEvaluation(),
          log: cancelOrder,
        ),
        conversationIdentity: cancelIdentity,
        conversationKey: 'peer-publishing-cancel',
        notificationId: cancelFixture.notificationId,
        metadata: cancelMetadata,
        retireCurrent: () async {
          cancelOrder.add('cancel');
          cancelCalls += 1;
        },
        publishNative: () async => fail('cancel recovery must not publish'),
        activeNotificationIds: () async =>
            fail('cancel recovery must not query active cards'),
      );
      expect(
        cancelled.disposition,
        DurableLocalNotificationEffectDisposition.cancelled,
      );
      expect(cancelCalls, 1);
      expect(cancelOrder, <String>['visibility', 'cancel']);
    },
  );
}

final class _Fixture {
  const _Fixture({
    required this.directory,
    required this.registry,
    required this.notificationId,
  });

  final Directory directory;
  final DurableConversationNotificationIdRegistry registry;
  final int notificationId;

  static Future<_Fixture> open(
    Directory directory,
    String conversationKey, {
    DateTime Function()? nowUtc,
  }) async {
    final store = LocalNotificationLedgerStore(directory: directory);
    final coordinator = DurableLocalNotificationEffectCoordinator(
      ledgerStore: store,
      nowUtc: nowUtc ?? () => DateTime.utc(2026, 8, 16, 12),
      effectTokenFactory: () => 'd' * 64,
    );
    final registry = DurableConversationNotificationIdRegistry(
      directory: directory,
      localNotificationEffectCoordinator: coordinator,
    );
    final id = await registry.resolve(
      conversationKey,
      activeNotificationIds: () async => const <Object?>[],
    );
    return _Fixture(
      directory: directory,
      registry: registry,
      notificationId: id,
    );
  }

  Future<LocalNotificationRecordV1> record({
    required String binding,
    required String correlation,
  }) async {
    final envelope = await LocalNotificationLedgerStore(
      directory: directory,
    ).read(currentOpaqueBinding: binding);
    return envelope!.records[correlation]!;
  }

  Future<void> initialize(String binding) async {
    final initialized = await LocalNotificationLedgerStore(
      directory: directory,
    ).initializeOrRebind(currentOpaqueBinding: binding);
    if (initialized == null) {
      throw StateError('test ledger initialization failed');
    }
  }
}

final class _MutableVisibility extends AppVisibilitySuppressionReader {
  _MutableVisibility({required this.evaluation, required this.log});

  AppVisibilityEvaluation evaluation;
  final List<String> log;

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async {
    log.add('visibility');
    return evaluation;
  }
}

AppVisibilityEvaluation _foregroundEvaluation({required bool maySuppress}) =>
    AppVisibilityEvaluation(
      isForegroundActive: true,
      maySuppress: maySuppress,
      lifecycle: AppVisibilityLifecycle.foregroundActive,
      revision: 7,
      lifecycleGeneration: 11,
    );

AppVisibilityEvaluation _backgroundEvaluation() =>
    const AppVisibilityEvaluation(
      isForegroundActive: false,
      maySuppress: false,
      lifecycle: AppVisibilityLifecycle.background,
      revision: 8,
      lifecycleGeneration: 12,
    );

DurableLocalNotificationEffectContext _context({
  required String label,
  required AppVisibilityConversationIdentity identity,
  required LocalNotificationProducerKind producer,
  required ReadDurableLocalNotificationCanonicalDisposition readFinal,
  LocalNotificationSourceCustody sourceCustody =
      LocalNotificationSourceCustody.sqlReady,
  LocalNotificationPresentationOwner presentationOwner =
      LocalNotificationPresentationOwner.mainApp,
}) => DurableLocalNotificationEffectContext(
  currentOpaqueBinding: 'v1:${_digest('binding-$label')}',
  eventCorrelation: _digest('event-$label'),
  conversationDigest: identity.digest,
  producerKind: producer,
  sourceCustody: sourceCustody,
  presentationOwner: presentationOwner,
  readFinalCanonicalDisposition: readFinal,
);

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
