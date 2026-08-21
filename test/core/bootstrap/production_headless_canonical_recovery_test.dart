import 'dart:async';
import 'dart:io';

import 'package:flutter_app/app/bootstrap/production_canonical_inbox_projection_composition.dart';
import 'package:flutter_app/app/bootstrap/production_headless_canonical_recovery.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_reconciliation_outbox_db_helpers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/canonical_recovery_runtime.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/headless_canonical_recovery_entrypoint.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:convert' show utf8;

import '../secure_storage/fake_secure_key_store.dart';

const _binding =
    'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _marker = CanonicalRecoveryMarker(generation: 7, binding: _binding);
const _testEncryptionKey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test(
    'TC-374-01 existing-only authority refuses a missing key without opening or creating state',
    () async {
      final productionKeyStore = FakeSecureKeyStore();
      await expectLater(
        openEncryptedDatabase(
          secureKeyStore: productionKeyStore,
          dbName: 'must-not-be-created.db',
          version: 116,
          requireExisting: true,
          onCreate: (_, _) async => fail('existing-only invoked onCreate'),
          onUpgrade: (_, _, _) async => fail('missing key invoked migration'),
        ),
        throwsA(
          isA<ExistingEncryptedDatabaseRequiredException>().having(
            (error) => error.reason,
            'reason',
            'missing_encryption_key',
          ),
        ),
      );
      expect(
        await productionKeyStore.containsKey(dbEncryptionKeyStorageKey),
        isFalse,
        reason: 'the shared production opener must not mint a recovery key',
      );

      final openerDirectory = await Directory.systemTemp.createTemp(
        'plan374-existing-opener-',
      );
      addTearDown(() => openerDirectory.delete(recursive: true));
      final missingDatabaseKeyStore = FakeSecureKeyStore();
      await missingDatabaseKeyStore.write(
        dbEncryptionKeyStorageKey,
        'raw:$_testEncryptionKey',
      );
      var missingDatabaseOpenCalls = 0;
      await expectLater(
        openEncryptedDatabase(
          secureKeyStore: missingDatabaseKeyStore,
          dbName: 'identity.db',
          version: 116,
          requireExisting: true,
          onCreate: (_, _) async => fail('missing DB invoked onCreate'),
          onUpgrade: (_, _, _) async => fail('missing DB invoked migration'),
          debugHooks: EncryptedDatabaseOpenDebugHooks(
            resolveDatabasesPath: () async => openerDirectory.path,
            isRawKeyDatabase: (_, _, _) async => true,
            openDatabase:
                (
                  _, {
                  required version,
                  required password,
                  required onConfigure,
                  required onCreate,
                  required onUpgrade,
                  required onDowngrade,
                }) async {
                  missingDatabaseOpenCalls += 1;
                  throw StateError('must not open a missing database');
                },
          ),
        ),
        throwsA(
          isA<ExistingEncryptedDatabaseRequiredException>().having(
            (error) => error.reason,
            'reason',
            'missing_database',
          ),
        ),
      );
      expect(missingDatabaseOpenCalls, 0);
      expect(File('${openerDirectory.path}/identity.db').existsSync(), isFalse);

      final malformedKeyStore = FakeSecureKeyStore();
      await malformedKeyStore.write(
        dbEncryptionKeyStorageKey,
        'raw:not-a-valid-key',
      );
      await expectLater(
        openEncryptedDatabase(
          secureKeyStore: malformedKeyStore,
          dbName: 'identity.db',
          version: 116,
          requireExisting: true,
          onCreate: (_, _) async {},
          onUpgrade: (_, _, _) async {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(File('${openerDirectory.path}/identity.db').existsSync(), isFalse);

      sqfliteFfiInit();
      final oldDatabasePath = '${openerDirectory.path}/identity.db';
      final oldDatabase = await databaseFactoryFfi.openDatabase(
        oldDatabasePath,
        options: OpenDatabaseOptions(
          version: 115,
          singleInstance: false,
          onCreate: (database, _) async {
            await database.execute('CREATE TABLE incumbent(id INTEGER)');
          },
        ),
      );
      await oldDatabase.close();
      var incumbentCreateCalls = 0;
      final upgradePairs = <(int, int)>[];
      final migratedDatabase = await openEncryptedDatabase(
        secureKeyStore: missingDatabaseKeyStore,
        dbName: 'identity.db',
        version: 116,
        requireExisting: true,
        onCreate: (_, _) async => incumbentCreateCalls += 1,
        onUpgrade: (_, oldVersion, newVersion) async {
          upgradePairs.add((oldVersion, newVersion));
        },
        debugHooks: EncryptedDatabaseOpenDebugHooks(
          resolveDatabasesPath: () async => openerDirectory.path,
          isRawKeyDatabase: (_, _, _) async => true,
          readExistingUserVersion: (path, _) async {
            final probe = await databaseFactoryFfi.openDatabase(
              path,
              options: OpenDatabaseOptions(
                readOnly: true,
                singleInstance: false,
              ),
            );
            try {
              final rows = await probe.rawQuery('PRAGMA user_version');
              return (rows.single.values.single as num).toInt();
            } finally {
              await probe.close();
            }
          },
          openDatabase:
              (
                path, {
                required version,
                required password,
                required onConfigure,
                required onCreate,
                required onUpgrade,
                required onDowngrade,
              }) => databaseFactoryFfi.openDatabase(
                path,
                options: OpenDatabaseOptions(
                  version: version,
                  singleInstance: false,
                  onConfigure: onConfigure,
                  onCreate: onCreate,
                  onUpgrade: onUpgrade,
                  onDowngrade: onDowngrade,
                ),
              ),
        ),
      );
      expect(incumbentCreateCalls, 0);
      expect(upgradePairs, <(int, int)>[(115, 116)]);
      expect(
        (await migratedDatabase.rawQuery(
          'PRAGMA user_version',
        )).single.values.single,
        116,
      );
      await migratedDatabase.close();

      final preOpenRefusal = _FactoryHarness(
        authority: _authority(recoveryWorkEnabled: false),
      );
      await expectLater(
        preOpenRefusal.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.deletedBatch,
        ),
        throwsA(
          isA<ProductionHeadlessCanonicalRecoveryRefused>().having(
            (error) => error.reason,
            'reason',
            'pre_open_authority_refused',
          ),
        ),
      );
      expect(preOpenRefusal.trace, isEmpty);

      final staleExpectedMarker = _FactoryHarness();
      await expectLater(
        staleExpectedMarker.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.deletedBatch,
          expectedMarker: const CanonicalRecoveryMarker(
            generation: 8,
            binding: _binding,
          ),
        ),
        throwsA(
          isA<ProductionHeadlessCanonicalRecoveryRefused>().having(
            (error) => error.reason,
            'reason',
            'pre_open_generation_changed',
          ),
        ),
      );
      expect(staleExpectedMarker.trace, isEmpty);

      final postOpenRefusal = _FactoryHarness(qualifyIdentity: false);
      await expectLater(
        postOpenRefusal.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.deletedBatch,
        ),
        throwsA(
          isA<ProductionHeadlessCanonicalRecoveryRefused>().having(
            (error) => error.reason,
            'reason',
            'post_open_authority_refused',
          ),
        ),
      );
      expect(postOpenRefusal.buildCount, 0);
      expect(postOpenRefusal.goOrNetworkEffectCount, 0);
      expect(postOpenRefusal.trace, <String>[
        'lease:$_binding',
        'open-existing-v116',
        'passive-identity',
        'qualify:false',
        'native:begin-drain',
        'native:await-quiescence',
        'close-database',
        'release:true',
      ]);

      final postOpenAuthorityChange = _FactoryHarness(
        authorityAfterQualification: _authority(
          marker: const CanonicalRecoveryMarker(
            generation: 8,
            binding: _binding,
          ),
        ),
      );
      await expectLater(
        postOpenAuthorityChange.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.deletedBatch,
          expectedMarker: _marker,
        ),
        throwsA(
          isA<ProductionHeadlessCanonicalRecoveryRefused>().having(
            (error) => error.reason,
            'reason',
            'post_open_native_authority_changed',
          ),
        ),
      );
      expect(postOpenAuthorityChange.buildCount, 0);
      expect(postOpenAuthorityChange.goOrNetworkEffectCount, 0);
      expect(
        postOpenAuthorityChange.trace,
        containsAllInOrder(<String>[
          'lease:$_binding',
          'open-existing-v116',
          'passive-identity',
          'qualify:true',
          'close-database',
          'release:true',
        ]),
      );

      final postOpenFinalizationCloseFailure = _FactoryHarness(
        failOpenAfterHandle: true,
        closeDatabaseSucceeds: false,
      );
      await expectLater(
        postOpenFinalizationCloseFailure.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.deletedBatch,
          expectedMarker: _marker,
        ),
        throwsA(isA<StateError>()),
      );
      expect(postOpenFinalizationCloseFailure.buildCount, 0);
      expect(postOpenFinalizationCloseFailure.leaseOwned, isTrue);
      expect(
        postOpenFinalizationCloseFailure.owner.lifecycleFacts.databaseClosed,
        isFalse,
      );
      expect(
        postOpenFinalizationCloseFailure.owner.lifecycleFacts.leaseReleased,
        isFalse,
      );
      expect(
        postOpenFinalizationCloseFailure.trace,
        containsAllInOrder(<String>[
          'open-existing-v116',
          'native:begin-drain',
          'native:await-quiescence',
          'close-database',
          'release:false',
        ]),
        reason:
            'the immediately reported handle remains owned on close failure',
      );

      for (final linked in <bool>[false, true]) {
        final accepted = _FactoryHarness(linked: linked);
        final session = await accepted.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.deletedBatch,
        );
        expect(session, isNotNull);
        expect(accepted.buildCount, 1);
        expect(
          accepted.trace,
          contains('build:${linked ? 'linked' : 'primary'}'),
        );
        expect(
          accepted.qualifiedPhysicalPeerId,
          linked ? 'linked-physical-peer' : 'account-peer',
        );
        final cleanup = await session!.emergencyCleanup();
        expect(cleanup.databaseClosed, isTrue);
        expect(cleanup.leaseReleased, isTrue);
      }

      final productionSource = _repoFile(
        'lib/app/bootstrap/production_headless_canonical_recovery.dart',
      ).readAsStringSync();
      expect(_occurrences(productionSource, 'requireExisting: true'), 1);
      expect(_occurrences(productionSource, 'onOpened: onOpened,'), 1);
      expect(productionSource, contains('loadPassiveIdentitySnapshot('));
      expect(productionSource, contains('runProductionOnUpgrade'));
      expect(
        productionSource,
        contains('selectNotificationCompletedOutcomePhysicalPeerId('),
      );
      expect(
        productionSource,
        isNot(contains('.loadIdentity()')),
        reason: 'headless qualification cannot publish foreground projections',
      );
    },
  );

  test(
    'TC-374-02 exhaustive typed direct group adapters and all custody totals converge without fallback',
    () async {
      final inboxSource = _repoFile(
        'lib/app/bootstrap/'
        'production_canonical_inbox_projection_composition.dart',
      ).readAsStringSync();
      final directSource = _repoFile(
        'lib/app/bootstrap/'
        'production_canonical_direct_replay_composition.dart',
      ).readAsStringSync();
      final groupSource = _repoFile(
        'lib/app/bootstrap/'
        'production_canonical_group_replay_composition.dart',
      ).readAsStringSync();
      final foregroundSource = _repoFile(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();

      const typedHeadlessHandlers = <String, String>{
        'direct chat and text mutation': 'replayRecoveredInboxChatMessage:',
        'direct reaction': 'replayRecoveredInboxReaction:',
        'direct introduction': 'replayRecoveredInboxIntroductionMessage:',
        'direct contact request': 'replayRecoveredInboxContactRequest:',
        'direct deletion': 'replayRecoveredInboxMessageDeletion:',
        'legacy group': 'final legacy = await drainGroupOfflineInbox(',
        'protected group content/bootstrap/authority':
            'replayRecoveredProtectedGroupEnvelope: protectedGroupReplay.replay,',
      };
      for (final entry in typedHeadlessHandlers.entries) {
        expect(
          inboxSource,
          contains(entry.value),
          reason: '${entry.key} must bind the real recovery-only P2P graph',
        );
      }
      for (final canonicalHandler in const <String>[
        'chatMessageListener().processIncomingMessage(',
        'resolveUnknownInboxSender(',
        'mapChatReplayOutcomeToDisposition(',
        'handleIncomingReaction(',
        'mapReactionReplayResultToDisposition(',
        'handleIncomingMessageDeletion(',
        'mapMessageDeletionReplayResultToDisposition(',
        'introductionListener().processIncomingMessage(',
        'contactRequestListener().processIncomingMessage(',
        'predecryptStagedInboxChatEntry(',
      ]) {
        expect(
          directSource,
          contains(canonicalHandler),
          reason: 'shared direct replay must call $canonicalHandler',
        );
      }
      for (final canonicalHandler in const <String>[
        'handleProtectedGroupContentReplay(',
        'handleLinkedGroupBootstrapEnvelope(',
        'handleProtectedGroupAuthority(',
        'handleAuthenticatedAuthorityEnvelope(',
        'handleAuthenticatedAuthorityReplayEnvelope(',
      ]) {
        expect(
          groupSource,
          contains(canonicalHandler),
          reason: 'shared protected replay must call $canonicalHandler',
        );
      }

      for (final sharedOwner in const <String>[
        'ProductionCanonicalDirectReplayComposition(',
        'buildProductionCanonicalDirectProjectionComposition(',
        'ProductionCanonicalProtectedGroupReplayComposition(',
      ]) {
        expect(inboxSource, contains(sharedOwner));
        expect(
          foregroundSource,
          contains(sharedOwner),
          reason: 'foreground and headless must share $sharedOwner',
        );
      }
      expect(
        _occurrences(
          foregroundSource,
          'ProductionCanonicalProtectedGroupAuthoritySupport(',
        ),
        1,
        reason: 'foreground must own one shared protected-authority support',
      );
      for (final sharedAuthorityImplementation in const <String>[
        'loadProtectedGroupContentAuthorityFromHistory(',
        'reconcileProtectedGroupContentForAuthority(',
        'hasPendingProtectedGroupContentAuthority(',
      ]) {
        expect(
          foregroundSource,
          isNot(contains(sharedAuthorityImplementation)),
          reason:
              'foreground must delegate $sharedAuthorityImplementation to '
              'the shared authority support',
        );
        expect(
          groupSource,
          contains(sharedAuthorityImplementation),
          reason:
              'shared protected replay must own '
              '$sharedAuthorityImplementation',
        );
      }
      expect(inboxSource, contains('recoveryOnly: true,'));
      expect(
        inboxSource,
        contains('drainProtectedGroupContentRecoveryFixedPoint()'),
      );
      expect(
        inboxSource,
        contains('LocalNotificationPresentationOwner.inboxReconciler'),
      );
      expect(inboxSource, contains('envelope.claimsSuspended'));
      expect(
        inboxSource,
        contains('accountMigrationNetworkGate:'),
        reason: 'headless may not use the permissive compatibility gate',
      );

      final contactStart = directSource.indexOf(
        'Future<RecoveredInboxReplayOutcome> replayContactRequest(',
      );
      final contactEnd = directSource.indexOf(
        'Future<String?> predecryptChatMessage(',
        contactStart,
      );
      expect(contactStart, greaterThanOrEqualTo(0));
      expect(contactEnd, greaterThan(contactStart));
      expect(
        _occurrences(
          directSource.substring(contactStart, contactEnd),
          'contactRequestListener().processIncomingMessage(message)',
        ),
        1,
        reason: 'contact requests must commit/confirm exactly once',
      );

      const converged = ProductionHeadlessCustodyTotals(
        directDisplay: 0,
        directReconciliation: 0,
        groupDisplay: 0,
        groupReconciliation: 0,
        unresolvedLedgerRecords: 0,
      );
      expect(converged.sqlTotal, 0);
      expect(converged.isConverged, isTrue);
      for (var pendingField = 0; pendingField < 5; pendingField++) {
        final pending = ProductionHeadlessCustodyTotals(
          directDisplay: pendingField == 0 ? 1 : 0,
          directReconciliation: pendingField == 1 ? 1 : 0,
          groupDisplay: pendingField == 2 ? 1 : 0,
          groupReconciliation: pendingField == 3 ? 1 : 0,
          unresolvedLedgerRecords: pendingField == 4 ? 1 : 0,
        );
        expect(
          pending.isConverged,
          isFalse,
          reason: 'pending custody field $pendingField cannot be hidden',
        );
      }

      sqfliteFfiInit();
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(database.close);
      for (final table in const <String>[
        'direct_notification_display_outbox',
        'direct_notification_reconciliation_outbox',
        'group_notification_display_outbox',
        'group_notification_reconciliation_outbox',
      ]) {
        await database.execute(
          'CREATE TABLE $table (id INTEGER PRIMARY KEY, status TEXT NOT NULL)',
        );
        await database.insert(table, <String, Object?>{
          'status': 'DEFERRED_NOT_READY',
        });
      }
      final realSqlTotals = ProductionHeadlessCustodyTotals(
        directDisplay: await dbCountAllDirectNotificationDisplayOutboxEntries(
          database,
        ),
        directReconciliation:
            await dbCountAllDirectNotificationReconciliationOutboxEntries(
              database,
            ),
        groupDisplay: await dbCountAllGroupNotificationDisplayOutboxEntries(
          database,
        ),
        groupReconciliation:
            await dbCountAllGroupNotificationReconciliationOutboxEntries(
              database,
            ),
        unresolvedLedgerRecords: 0,
      );
      expect(realSqlTotals.sqlTotal, 4);
      expect(realSqlTotals.isConverged, isFalse);
      for (final table in const <String>[
        'direct_notification_display_outbox',
        'direct_notification_reconciliation_outbox',
        'group_notification_display_outbox',
        'group_notification_reconciliation_outbox',
      ]) {
        await database.delete(table);
      }
      expect(
        ProductionHeadlessCustodyTotals(
          directDisplay: await dbCountAllDirectNotificationDisplayOutboxEntries(
            database,
          ),
          directReconciliation:
              await dbCountAllDirectNotificationReconciliationOutboxEntries(
                database,
              ),
          groupDisplay: await dbCountAllGroupNotificationDisplayOutboxEntries(
            database,
          ),
          groupReconciliation:
              await dbCountAllGroupNotificationReconciliationOutboxEntries(
                database,
              ),
          unresolvedLedgerRecords: 0,
        ).isConverged,
        isTrue,
      );
    },
  );

  test(
    'TC-375-04 fixed wake carries no event authority and canonical drain remains inbox reconciler',
    () async {
      sqfliteFfiInit();
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(database.close);
      for (final table in const <String>[
        'direct_notification_display_outbox',
        'direct_notification_reconciliation_outbox',
        'group_notification_display_outbox',
        'group_notification_reconciliation_outbox',
      ]) {
        await database.execute(
          'CREATE TABLE $table (id INTEGER PRIMARY KEY, status TEXT NOT NULL)',
        );
      }
      // One canonical direct message waits in SQL custody; nothing else.
      await database.insert(
        'direct_notification_display_outbox',
        <String, Object?>{'status': 'DEFERRED_NOT_READY'},
      );

      final ledgerDirectory = await Directory.systemTemp.createTemp(
        'plan375-fixed-wake-ledger-',
      );
      addTearDown(() => ledgerDirectory.delete(recursive: true));
      final ledgerStore = LocalNotificationLedgerStore(
        directory: ledgerDirectory,
      );
      expect(
        await ledgerStore.initializeOrRebind(currentOpaqueBinding: _binding),
        isNotNull,
      );
      final registry = DurableConversationNotificationIdRegistry(
        directory: ledgerDirectory,
        localNotificationEffectCoordinator:
            DurableLocalNotificationEffectCoordinator(
              ledgerStore: ledgerStore,
              nowUtc: () => DateTime.parse('2026-08-16T12:00:01.000Z').toUtc(),
              effectTokenFactory: () => 'f' * 64,
            ),
      );

      // The exact fixed invocation is only a durable mailbox signal: its
      // parse admits reason/nonce/binding/generation and nothing else — no
      // FCM message ID, collapse key, priority or TTL survives into Dart.
      final invocation = HeadlessCanonicalRecoveryInvocation.parse(
        const <String>['fixed_wake', 'nonce-tc-375-04', _binding, '7'],
      );
      expect(invocation.reason, CanonicalRecoveryReason.fixedWake);
      expect(invocation.identityPayload().keys.toSet(), <String>{
        'reason',
        'nonce',
        'binding',
        'generation',
      });
      // Before any canonical drain the real ledger holds zero records: the
      // identity-free wake minted no event, correlation or custody authority.
      final preDrain = await ledgerStore.read(currentOpaqueBinding: _binding);
      expect(preDrain, isNotNull);
      expect(preDrain!.records, isEmpty);

      const messageId = 'direct-message-tc-375-04';
      const physicalPeerId = 'physical-peer-tc-375-04';
      final eventCorrelation =
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: physicalPeerId,
            producerKind:
                NotificationCompletedOutcomeProducerKind.directMessage,
            eventKey: messageId,
          )!;
      final conversationIdentity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'direct-peer-tc-375-04',
      )!;

      Future<ProductionHeadlessCustodyTotals> readTotals() async {
        final envelope = await ledgerStore.read(currentOpaqueBinding: _binding);
        final unresolvedLedgerRecords = envelope == null
            ? 1
            : (envelope.claimsSuspended ? 1 : 0) +
                  envelope.records.values
                      .where(
                        (record) =>
                            record.effectPhase !=
                            LocalNotificationEffectPhase.settled,
                      )
                      .length;
        return ProductionHeadlessCustodyTotals(
          directDisplay: await dbCountAllDirectNotificationDisplayOutboxEntries(
            database,
          ),
          directReconciliation:
              await dbCountAllDirectNotificationReconciliationOutboxEntries(
                database,
              ),
          groupDisplay: await dbCountAllGroupNotificationDisplayOutboxEntries(
            database,
          ),
          groupReconciliation:
              await dbCountAllGroupNotificationReconciliationOutboxEntries(
                database,
              ),
          unresolvedLedgerRecords: unresolvedLedgerRecords,
        );
      }

      var nativePosts = 0;
      Future<void> materializeCanonicalDirectMessage() async {
        final notificationId = await registry.resolve(
          'direct-peer-tc-375-04',
          activeNotificationIds: () async => const <Object?>[],
        );
        // The Plan-374 drain authenticates and persists the current direct
        // row first, then materializes notification custody strictly as
        // INBOX_RECONCILER over SQL_READY source custody through Plan 372.
        final effect = await registry.runFinalEffect(
          context: DurableLocalNotificationEffectContext(
            currentOpaqueBinding: _binding,
            eventCorrelation: eventCorrelation,
            conversationDigest: conversationIdentity.digest,
            producerKind: LocalNotificationProducerKind.directMessage,
            sourceCustody: LocalNotificationSourceCustody.sqlReady,
            presentationOwner:
                LocalNotificationPresentationOwner.inboxReconciler,
            readFinalCanonicalDisposition: () async =>
                DurableLocalNotificationCanonicalDisposition.eligible,
          ),
          appVisibility: _HeadlessBackgroundVisibility(),
          conversationIdentity: conversationIdentity,
          conversationKey: 'direct-peer-tc-375-04',
          notificationId: notificationId,
          metadata: ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: eventCorrelation,
            generation: 'ledger:$eventCorrelation',
          ),
          retireCurrent: () async {},
          publishNative: () async {
            nativePosts += 1;
          },
        );
        expect(
          effect.disposition,
          DurableLocalNotificationEffectDisposition.osPosted,
        );
        final settled = await registry.settleSqlReadyEffect(
          currentOpaqueBinding: _binding,
          eventCorrelation: eventCorrelation,
          expectedRevision: effect.receipt!.recordRevision,
        );
        expect(settled, isNotNull);
        await database.delete('direct_notification_display_outbox');
      }

      final acknowledged = <CanonicalRecoveryMarker>[];
      var markerPresent = true;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => _binding,
        loadPendingMarker: () async => markerPresent ? _marker : null,
        acquireSession: ({required binding, required reason}) async {
          expect(reason, CanonicalRecoveryReason.fixedWake);
          return _Tc37504Session(
            drainDirect: () async {
              await materializeCanonicalDirectMessage();
              return const CanonicalRecoveryDrainOutcome(
                isSuccessful: true,
                hasMore: false,
              );
            },
            settle: () async {
              final totals = await readTotals();
              return CanonicalRecoveryProjectionOutcome(
                isSuccessful: true,
                hasPendingWork: !totals.isConverged,
              );
            },
          );
        },
        acknowledgeMarker: (marker, {authorityRevision}) async {
          if (marker != _marker || !markerPresent) return false;
          markerPresent = false;
          acknowledged.add(marker);
          return true;
        },
      );

      final result = await runtime.run(
        CanonicalRecoveryReason.fixedWake,
        expectedBinding: _binding,
        expectedMarker: _marker,
      );
      expect(result.disposition, CanonicalRecoveryDisposition.succeeded);
      expect(nativePosts, 1);
      expect(acknowledged, <CanonicalRecoveryMarker>[_marker]);
      expect((await readTotals()).isConverged, isTrue);

      // The one real ledger record is canonical custody, not wake authority:
      // exact INBOX_RECONCILER over SQL_READY, keyed by the authenticated
      // message correlation. Nothing anywhere derives from the wake nonce,
      // recovery generation, or an FCM transport hint, and no record claims
      // ANDROID_PUSH_SERVICE or RELAY_VERIFIED_UNACKED custody.
      final envelope = (await ledgerStore.read(
        currentOpaqueBinding: _binding,
      ))!;
      expect(envelope.records, hasLength(1));
      final record = envelope.records.values.single;
      expect(
        record.presentationOwner,
        LocalNotificationPresentationOwner.inboxReconciler,
      );
      expect(record.sourceCustody, LocalNotificationSourceCustody.sqlReady);
      expect(
        record.presentationState,
        LocalNotificationPresentationState.osPosted,
      );
      expect(record.effectPhase, LocalNotificationEffectPhase.settled);
      expect(envelope.records.keys.single, eventCorrelation);
      final ledgerBytes = StringBuffer();
      await for (final entity in ledgerDirectory.list(recursive: true)) {
        if (entity is File) {
          ledgerBytes.write(
            utf8.decode(await entity.readAsBytes(), allowMalformed: true),
          );
        }
      }
      final persistedLedger = ledgerBytes.toString();
      expect(persistedLedger, isNot(contains('nonce-tc-375-04')));
      expect(persistedLedger, isNot(contains('fixed_wake')));
      expect(persistedLedger, isNot(contains('ANDROID_PUSH_SERVICE')));
      expect(persistedLedger, isNot(contains('RELAY_VERIFIED_UNACKED')));
      expect(persistedLedger, contains('INBOX_RECONCILER'));

      // The wake fields also never become a correlation: the Plan-369
      // projection accepts only authenticated event keys, and hashing the
      // generation would collide with nothing the ledger recognizes.
      expect(
        tryComputeNotificationCompletedOutcomeCorrelation(
          physicalPeerId: physicalPeerId,
          producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
          eventKey: '',
        ),
        isNull,
      );
      expect(
        sha256.convert(utf8.encode('7')).toString(),
        isNot(eventCorrelation),
      );
    },
  );

  test(
    'TC-393-13 authenticated direct reaction settles through inbox reconciler',
    () async {
      sqfliteFfiInit();
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(database.close);
      for (final table in const <String>[
        'direct_notification_display_outbox',
        'direct_notification_reconciliation_outbox',
        'group_notification_display_outbox',
        'group_notification_reconciliation_outbox',
      ]) {
        await database.execute(
          'CREATE TABLE $table (id INTEGER PRIMARY KEY, status TEXT NOT NULL)',
        );
      }
      await database.insert(
        'direct_notification_display_outbox',
        <String, Object?>{'status': 'DEFERRED_NOT_READY'},
      );

      final ledgerDirectory = await Directory.systemTemp.createTemp(
        'plan393-fixed-wake-direct-reaction-ledger-',
      );
      addTearDown(() => ledgerDirectory.delete(recursive: true));
      final ledgerStore = LocalNotificationLedgerStore(
        directory: ledgerDirectory,
      );
      expect(
        await ledgerStore.initializeOrRebind(currentOpaqueBinding: _binding),
        isNotNull,
      );
      final registry = DurableConversationNotificationIdRegistry(
        directory: ledgerDirectory,
        localNotificationEffectCoordinator:
            DurableLocalNotificationEffectCoordinator(
              ledgerStore: ledgerStore,
              nowUtc: () => DateTime.parse('2026-08-21T12:00:01.000Z').toUtc(),
              effectTokenFactory: () => '3' * 64,
            ),
      );

      final invocation = HeadlessCanonicalRecoveryInvocation.parse(
        const <String>['fixed_wake', 'nonce-tc-393-13', _binding, '7'],
      );
      expect(invocation.reason, CanonicalRecoveryReason.fixedWake);
      expect(invocation.identityPayload().keys.toSet(), <String>{
        'reason',
        'nonce',
        'binding',
        'generation',
      });

      const reactionId = 'direct-reaction-tc-393-13';
      const physicalPeerId = 'physical-peer-tc-393-13';
      final selectedEventKey = trySelectNotificationCompletedOutcomeEventKey(
        producerKind: NotificationCompletedOutcomeProducerKind.directReaction,
        authenticatedEnvelope: const <String, Object?>{
          'reactionId': reactionId,
          'messageId': 'non-authoritative-message-id',
        },
      );
      expect(selectedEventKey, reactionId);
      final eventCorrelation =
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: physicalPeerId,
            producerKind:
                NotificationCompletedOutcomeProducerKind.directReaction,
            eventKey: selectedEventKey!,
          )!;
      final conversationIdentity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: 'direct-peer-tc-393-13',
      )!;

      Future<ProductionHeadlessCustodyTotals> readTotals() async {
        final envelope = await ledgerStore.read(currentOpaqueBinding: _binding);
        final unresolvedLedgerRecords = envelope == null
            ? 1
            : (envelope.claimsSuspended ? 1 : 0) +
                  envelope.records.values
                      .where(
                        (record) =>
                            record.effectPhase !=
                            LocalNotificationEffectPhase.settled,
                      )
                      .length;
        return ProductionHeadlessCustodyTotals(
          directDisplay: await dbCountAllDirectNotificationDisplayOutboxEntries(
            database,
          ),
          directReconciliation:
              await dbCountAllDirectNotificationReconciliationOutboxEntries(
                database,
              ),
          groupDisplay: await dbCountAllGroupNotificationDisplayOutboxEntries(
            database,
          ),
          groupReconciliation:
              await dbCountAllGroupNotificationReconciliationOutboxEntries(
                database,
              ),
          unresolvedLedgerRecords: unresolvedLedgerRecords,
        );
      }

      var nativePosts = 0;
      Future<void> materializeAuthenticatedReaction() async {
        final notificationId = await registry.resolve(
          'direct-peer-tc-393-13',
          activeNotificationIds: () async => const <Object?>[],
        );
        final effect = await registry.runFinalEffect(
          context: DurableLocalNotificationEffectContext(
            currentOpaqueBinding: _binding,
            eventCorrelation: eventCorrelation,
            conversationDigest: conversationIdentity.digest,
            producerKind: LocalNotificationProducerKind.directReaction,
            sourceCustody: LocalNotificationSourceCustody.sqlReady,
            presentationOwner:
                LocalNotificationPresentationOwner.inboxReconciler,
            readFinalCanonicalDisposition: () async =>
                DurableLocalNotificationCanonicalDisposition.eligible,
          ),
          appVisibility: _HeadlessBackgroundVisibility(),
          conversationIdentity: conversationIdentity,
          conversationKey: 'direct-peer-tc-393-13',
          notificationId: notificationId,
          metadata: ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.reaction,
            eventIdentity: eventCorrelation,
            generation: 'ledger:$eventCorrelation',
          ),
          retireCurrent: () async {},
          publishNative: () async {
            nativePosts += 1;
          },
        );
        expect(
          effect.disposition,
          DurableLocalNotificationEffectDisposition.osPosted,
        );
        final settled = await registry.settleSqlReadyEffect(
          currentOpaqueBinding: _binding,
          eventCorrelation: eventCorrelation,
          expectedRevision: effect.receipt!.recordRevision,
        );
        expect(settled, isNotNull);
        await database.delete('direct_notification_display_outbox');
      }

      final acknowledged = <CanonicalRecoveryMarker>[];
      var markerPresent = true;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => _binding,
        loadPendingMarker: () async => markerPresent ? _marker : null,
        acquireSession: ({required binding, required reason}) async {
          expect(binding, _binding);
          expect(reason, CanonicalRecoveryReason.fixedWake);
          return _Tc37504Session(
            drainDirect: () async {
              await materializeAuthenticatedReaction();
              return const CanonicalRecoveryDrainOutcome(
                isSuccessful: true,
                hasMore: false,
              );
            },
            settle: () async {
              final totals = await readTotals();
              return CanonicalRecoveryProjectionOutcome(
                isSuccessful: true,
                hasPendingWork: !totals.isConverged,
              );
            },
          );
        },
        acknowledgeMarker: (marker, {authorityRevision}) async {
          if (marker != _marker || !markerPresent) return false;
          markerPresent = false;
          acknowledged.add(marker);
          return true;
        },
      );

      final result = await runtime.run(
        CanonicalRecoveryReason.fixedWake,
        expectedBinding: _binding,
        expectedMarker: _marker,
      );
      expect(result.disposition, CanonicalRecoveryDisposition.succeeded);
      expect(nativePosts, 1);
      expect(acknowledged, <CanonicalRecoveryMarker>[_marker]);
      expect(markerPresent, isFalse);
      expect((await readTotals()).isConverged, isTrue);

      final envelope = (await ledgerStore.read(
        currentOpaqueBinding: _binding,
      ))!;
      expect(envelope.records, hasLength(1));
      final record = envelope.records.values.single;
      expect(envelope.records.keys.single, eventCorrelation);
      expect(record.producerKind, LocalNotificationProducerKind.directReaction);
      expect(record.sourceCustody, LocalNotificationSourceCustody.sqlReady);
      expect(
        record.presentationOwner,
        LocalNotificationPresentationOwner.inboxReconciler,
      );
      expect(
        record.presentationState,
        LocalNotificationPresentationState.osPosted,
      );
      expect(record.effectPhase, LocalNotificationEffectPhase.settled);

      final persisted = StringBuffer();
      await for (final entity in ledgerDirectory.list(recursive: true)) {
        if (entity is File) {
          persisted.write(
            utf8.decode(await entity.readAsBytes(), allowMalformed: true),
          );
        }
      }
      final persistedLedger = persisted.toString();
      expect(persistedLedger, contains('direct_reaction'));
      expect(persistedLedger, contains('SQL_READY'));
      expect(persistedLedger, contains('INBOX_RECONCILER'));
      expect(persistedLedger, contains('SETTLED'));
      expect(persistedLedger, isNot(contains('nonce-tc-393-13')));
      expect(persistedLedger, isNot(contains('fixed_wake')));
      expect(persistedLedger, isNot(contains('ANDROID_PUSH_SERVICE')));
      expect(persistedLedger, isNot(contains('RELAY_VERIFIED_UNACKED')));
    },
  );

  test(
    'TC-374-04 admission seals awaits re-settles and same-owner emergency cleanup preserves ordered facts',
    () async {
      final trace = <String>[];
      final barrier = ProductionHeadlessRecoveryAdmissionBarrier();
      final admittedRelease = Completer<void>();
      var rejectedOffers = 0;
      var rejectedHandlerEffects = 0;
      expect(
        barrier.tryAdmit(() async {
          trace.add('admitted:start');
          await admittedRelease.future;
          trace.add('admitted:done');
        }, onRejected: () => rejectedOffers++),
        isTrue,
      );
      final session = ProductionHeadlessCanonicalRecoverySession(
        delegates: _sessionDelegates(trace: trace, barrier: barrier),
        closeDatabase: () async {
          trace.add('close');
          return true;
        },
        releaseOwnership: ({required databaseClosed}) async {
          trace.add('release:$databaseClosed');
          return databaseClosed;
        },
      );
      var acknowledged = 0;
      final runtime = CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => _binding,
        loadPendingMarker: () async => _marker,
        acquireSession: ({required binding, required reason}) async => session,
        acknowledgeMarker: (_, {authorityRevision}) async {
          acknowledged++;
          trace.add('ack');
          return true;
        },
      );

      final run = runtime.run(CanonicalRecoveryReason.deletedBatch);
      await _waitUntil(() => barrier.isSealed);
      expect(
        barrier.tryAdmit(
          () async {
            rejectedHandlerEffects++;
          },
          onRejected: () {
            rejectedOffers++;
            trace.add('post-seal:durable-retry');
          },
        ),
        isFalse,
      );
      expect(rejectedHandlerEffects, 0);
      expect(acknowledged, 0);
      admittedRelease.complete();

      final result = await run;
      expect(result.disposition, CanonicalRecoveryDisposition.retry);
      expect(result.failureReason, 'post_seal_offer_retained_for_retry');
      expect(rejectedOffers, 1);
      expect(rejectedHandlerEffects, 0);
      expect(acknowledged, 0);
      expect(
        trace,
        containsAllInOrder(<String>[
          'runtime',
          'transport',
          'direct',
          'group',
          'settle:preliminary',
          'seal:external',
          'await:external',
          'post-seal:durable-retry',
          'admitted:done',
          'group:stop',
          'settle:authoritative',
          'owners:dispose',
          'go:quiesce',
          'close',
          'release:true',
        ]),
      );
      expect(trace, isNot(contains('ack')));

      final emergencyTrace = <String>[];
      final quiesceRelease = Completer<void>();
      final emergencySession = ProductionHeadlessCanonicalRecoverySession(
        delegates: _sessionDelegates(
          trace: emergencyTrace,
          barrier: ProductionHeadlessRecoveryAdmissionBarrier(),
          quiesceRelease: quiesceRelease,
        ),
        closeDatabase: () async {
          emergencyTrace.add('close');
          return true;
        },
        releaseOwnership: ({required databaseClosed}) async {
          emergencyTrace.add('release:$databaseClosed');
          return databaseClosed;
        },
      );
      final firstCleanup = emergencySession.emergencyCleanup();
      final secondCleanup = emergencySession.emergencyCleanup();
      expect(identical(firstCleanup, secondCleanup), isTrue);
      await _waitUntil(() => emergencyTrace.contains('go:quiesce'));
      expect(emergencySession.lifecycleFacts.databaseClosed, isFalse);
      expect(emergencySession.lifecycleFacts.leaseReleased, isFalse);
      quiesceRelease.complete();
      final cleanup = await firstCleanup;
      expect(cleanup.databaseClosed, isTrue);
      expect(cleanup.leaseReleased, isTrue);
      expect(
        emergencyTrace,
        containsAllInOrder(<String>[
          'seal:external',
          'await:external',
          'group:stop',
          'owners:dispose',
          'go:quiesce',
          'close',
          'release:true',
        ]),
      );

      for (final failure in <String>['seal', 'groupStop', 'dispose']) {
        final failedTrace = <String>[];
        final failedSession = ProductionHeadlessCanonicalRecoverySession(
          delegates: _sessionDelegates(
            trace: failedTrace,
            barrier: ProductionHeadlessRecoveryAdmissionBarrier(),
            failAt: failure,
          ),
          closeDatabase: () async {
            failedTrace.add('close');
            return true;
          },
          releaseOwnership: ({required databaseClosed}) async {
            failedTrace.add('release:$databaseClosed');
            return databaseClosed;
          },
        );
        final failedCleanup = await failedSession.emergencyCleanup();
        expect(failedCleanup.databaseClosed, isFalse, reason: failure);
        expect(failedCleanup.leaseReleased, isFalse, reason: failure);
        expect(
          failedTrace,
          containsAllInOrder(<String>['go:quiesce', 'release:false']),
          reason: failure,
        );
        expect(failedTrace, isNot(contains('close')), reason: failure);
      }

      final retrySealTrace = <String>[];
      final retrySealSession = ProductionHeadlessCanonicalRecoverySession(
        delegates: _sessionDelegates(
          trace: retrySealTrace,
          barrier: ProductionHeadlessRecoveryAdmissionBarrier(),
          externalSealFailures: 1,
        ),
        closeDatabase: () async {
          retrySealTrace.add('close');
          return true;
        },
        releaseOwnership: ({required databaseClosed}) async {
          retrySealTrace.add('release:$databaseClosed');
          return databaseClosed;
        },
      );
      final firstSealCleanup = await retrySealSession.emergencyCleanup();
      expect(firstSealCleanup.databaseClosed, isFalse);
      expect(firstSealCleanup.leaseReleased, isFalse);
      expect(retrySealTrace, isNot(contains('close')));

      final retriedSealCleanup = await retrySealSession.emergencyCleanup();
      expect(retriedSealCleanup.databaseClosed, isTrue);
      expect(retriedSealCleanup.leaseReleased, isTrue);
      expect(
        retrySealTrace.where((event) => event == 'seal:external'),
        hasLength(2),
        reason: 'a failed synchronous external seal must be retried',
      );
      expect(
        retrySealTrace,
        containsAllInOrder(<String>[
          'seal:external',
          'release:false',
          'seal:external',
          'await:external',
          'group:stop',
          'owners:dispose',
          'close',
          'release:true',
        ]),
      );

      const provenConstructionCleanup =
          ProductionCanonicalRecoveryConstructionCleanupProof(
            admissionSealedAndDrained: true,
            dartOwnersQuiesced: true,
            runtimeQuiesced: true,
          );
      expect(provenConstructionCleanup.isProven, isTrue);
      expect(
        const ProductionCanonicalRecoveryConstructionCleanupProof.unproven()
            .isProven,
        isFalse,
      );

      Future<ProductionCanonicalRecoveryCompositionConstructionFailure>
      runRealConstructionCleanup(
        ProductionCanonicalRecoveryPartialConstructionCleanup cleanup,
      ) async {
        try {
          await throwProductionCanonicalRecoveryConstructionFailure(
            cause: StateError('forced mid-construction failure'),
            causeStackTrace: StackTrace.current,
            cleanup: cleanup,
          );
        } on ProductionCanonicalRecoveryCompositionConstructionFailure catch (
          failure
        ) {
          return failure;
        }
      }

      final constructionTrace = <String>[];
      final realProvenFailure = await runRealConstructionCleanup(
        ProductionCanonicalRecoveryPartialConstructionCleanup(
          sealAndAwaitAdmission: () async => constructionTrace.add('seal'),
          stopDartOwners: <Future<void> Function()>[
            () async => constructionTrace.add('listener:stop'),
          ],
          disposeDartOwners: <void Function()>[
            () => constructionTrace.add('owner:dispose'),
          ],
          stopRuntime: () async {
            constructionTrace.add('runtime:stop');
            return true;
          },
          disposeRuntimeOwners: <void Function()>[
            () => constructionTrace.add('runtime:dispose'),
          ],
        ),
      );
      expect(realProvenFailure.cleanupProof.isProven, isTrue);
      expect(constructionTrace, <String>[
        'seal',
        'listener:stop',
        'owner:dispose',
        'runtime:stop',
        'runtime:dispose',
      ]);

      final realUnprovenFailure = await runRealConstructionCleanup(
        ProductionCanonicalRecoveryPartialConstructionCleanup(
          sealAndAwaitAdmission: () async => throw StateError('seal failed'),
          disposeDartOwners: <void Function()>[
            () => throw StateError('dispose failed'),
          ],
          stopRuntime: () async => false,
          disposeRuntimeOwners: <void Function()>[
            () => fail('runtime dispose cannot follow a failed stop'),
          ],
        ),
      );
      expect(
        realUnprovenFailure.cleanupProof.admissionSealedAndDrained,
        isFalse,
      );
      expect(realUnprovenFailure.cleanupProof.dartOwnersQuiesced, isFalse);
      expect(realUnprovenFailure.cleanupProof.runtimeQuiesced, isFalse);

      final provenConstructionHarness = _FactoryHarness(
        constructionFailureProof: provenConstructionCleanup,
      );
      await expectLater(
        provenConstructionHarness.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.deletedBatch,
          expectedMarker: _marker,
        ),
        throwsA(
          isA<ProductionCanonicalRecoveryCompositionConstructionFailure>(),
        ),
      );
      expect(
        provenConstructionHarness.owner.lifecycleFacts.databaseClosed,
        isTrue,
      );
      expect(
        provenConstructionHarness.owner.lifecycleFacts.leaseReleased,
        isTrue,
      );
      expect(
        provenConstructionHarness.trace,
        containsAllInOrder(<String>[
          'build:primary',
          'close-database',
          'release:true',
        ]),
      );

      final unprovenConstructionHarness = _FactoryHarness(
        constructionFailureProof:
            const ProductionCanonicalRecoveryConstructionCleanupProof.unproven(),
      );
      await expectLater(
        unprovenConstructionHarness.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.deletedBatch,
          expectedMarker: _marker,
        ),
        throwsA(
          isA<ProductionCanonicalRecoveryCompositionConstructionFailure>(),
        ),
      );
      expect(
        unprovenConstructionHarness.owner.lifecycleFacts.databaseClosed,
        isFalse,
      );
      expect(
        unprovenConstructionHarness.owner.lifecycleFacts.leaseReleased,
        isFalse,
      );
      expect(
        unprovenConstructionHarness.trace,
        isNot(contains('close-database')),
      );
      expect(unprovenConstructionHarness.trace, contains('release:false'));

      final nativeOwnedStopHarness = _NativeGatewayOwnerHarness();
      expect(
        await nativeOwnedStopHarness.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.deletedBatch,
          expectedMarker: _marker,
        ),
        isNotNull,
      );
      final nativeOwnedCleanup = await nativeOwnedStopHarness.owner
          .emergencyCleanup();
      expect(nativeOwnedCleanup.databaseClosed, isTrue);
      expect(nativeOwnedCleanup.leaseReleased, isTrue);
      expect(
        nativeOwnedStopHarness.trace,
        containsAllInOrder(<String>[
          'native:lease-acquire',
          'database:open',
          'native:runtime-attach',
          'seal:external',
          'await:external',
          'group:stop',
          'owners:dispose',
          'native:begin-drain',
          'native:host-stop-and-quiesce',
          'runtime-owners:dispose',
          'database:close',
          'native:lease-release:true',
        ]),
      );
      expect(
        nativeOwnedStopHarness.trace,
        isNot(contains('go:quiesce')),
        reason: 'native drain owns the sole Go StopNode transition',
      );

      final productionSource = _repoFile(
        'lib/app/bootstrap/production_headless_canonical_recovery.dart',
      ).readAsStringSync();
      final compositionSource = _repoFile(
        'lib/app/bootstrap/'
        'production_canonical_inbox_projection_composition.dart',
      ).readAsStringSync();
      for (final exactFence in const <String>[
        'final acquisition = _acquisitionInFlight;',
        'await acquisition;',
        '_database = database;',
        'delegates.sealExternalAdmission();',
        'delegates.awaitExternalInFlight()',
        'beginOwnershipDrain: _writableSession.beginDrain,',
        'awaitOwnershipQuiescence: _writableSession.awaitRuntimeQuiescence,',
      ]) {
        expect(productionSource, contains(exactFence));
      }
      for (final constructionFence in const <String>[
        'ProductionCanonicalRecoveryCompositionConstructionFailure(',
        'admissionSealedAndDrained: admissionSealedAndDrained,',
        'dartOwnersQuiesced: dartOwnersQuiesced,',
        'runtimeQuiesced: runtimeQuiesced,',
      ]) {
        expect(
          compositionSource,
          contains(constructionFence),
          reason: 'real composition must report $constructionFence',
        );
      }
      for (final backendFence in const <String>[
        'ProductionCanonicalRecoveryConstructionCleanupProof.unproven()',
        '_partialCompositionCleanupProof = failure.cleanupProof;',
        'constructionProof.admissionSealedAndDrained',
        'constructionProof.dartOwnersQuiesced',
        'constructionProof?.runtimeQuiesced ?? true',
        'dartOwnersQuiesced && runtimeQuiesced && _databaseClosed',
      ]) {
        expect(
          productionSource,
          contains(backendFence),
          reason: 'partial graph cleanup must retain $backendFence',
        );
      }
      final ownedQuiesceStart = productionSource.indexOf(
        'ProductionHeadlessRecoverySessionDelegates '
        '_bindOwnedRuntimeQuiescence(',
      );
      final ownedQuiesceEnd = productionSource.indexOf(
        'Future<bool> _closeTrackedDatabase()',
        ownedQuiesceStart,
      );
      expect(ownedQuiesceStart, greaterThanOrEqualTo(0));
      expect(ownedQuiesceEnd, greaterThan(ownedQuiesceStart));
      final ownedQuiesceSource = productionSource.substring(
        ownedQuiesceStart,
        ownedQuiesceEnd,
      );
      final nativeBegin = ownedQuiesceSource.indexOf(
        'if (!await _beginOwnershipDrain())',
      );
      final nativeAwait = ownedQuiesceSource.indexOf(
        'if (!await _awaitOwnershipQuiescence())',
      );
      final runtimeOwnerDispose = ownedQuiesceSource.indexOf(
        'built.disposeRuntimeOwnersAfterNativeQuiescence()',
      );
      expect(nativeBegin, greaterThanOrEqualTo(0));
      expect(nativeAwait, greaterThan(nativeBegin));
      expect(runtimeOwnerDispose, greaterThan(nativeAwait));
      expect(
        ownedQuiesceSource,
        isNot(contains('built.quiesceRuntime')),
        reason: 'Dart cannot send StopNode after native enters DRAINING',
      );

      final runtimeDisposalStart = compositionSource.indexOf(
        'Future<bool> '
        'performRuntimeOwnerDisposalAfterNativeQuiescence()',
      );
      final runtimeDisposalEnd = compositionSource.indexOf(
        'Future<bool> disposeRuntimeOwnersAfterNativeQuiescence()',
        runtimeDisposalStart,
      );
      expect(runtimeDisposalStart, greaterThanOrEqualTo(0));
      expect(runtimeDisposalEnd, greaterThan(runtimeDisposalStart));
      final runtimeDisposalSource = compositionSource.substring(
        runtimeDisposalStart,
        runtimeDisposalEnd,
      );
      expect(runtimeDisposalSource, isNot(contains('stopNode()')));
      final p2pDispose = runtimeDisposalSource.indexOf('p2pService.dispose();');
      final bridgeDispose = runtimeDisposalSource.indexOf('bridge.dispose();');
      expect(p2pDispose, greaterThanOrEqualTo(0));
      expect(
        bridgeDispose,
        greaterThan(p2pDispose),
        reason: 'Dart P2P handlers detach before the bridge is disposed',
      );
      expect(
        _occurrences(compositionSource, 'stopRuntime: p2pService?.stopNode'),
        1,
        reason: 'only pre-session construction rollback may stop Go directly',
      );
      expect(
        _occurrences(
          productionSource,
          'final class ProductionHeadlessCanonicalRecoveryAcquisitionOwner',
        ),
        1,
        reason: 'production and host proof share one acquisition state machine',
      );
      expect(
        productionSource,
        isNot(contains('ProductionHeadlessCanonicalRecoveryGraphFactory')),
      );
      final acquisitionOwnerStart = productionSource.indexOf(
        'final class ProductionHeadlessCanonicalRecoveryAcquisitionOwner',
      );
      final ownerAcquireStart = productionSource.indexOf(
        'Future<ProductionHeadlessOwnedRecoverySession?> acquireSession({',
        acquisitionOwnerStart,
      );
      final ownerAcquireEnd = productionSource.indexOf(
        'Future<ProductionHeadlessOwnedRecoverySession?> _acquireSession({',
        ownerAcquireStart,
      );
      expect(acquisitionOwnerStart, greaterThanOrEqualTo(0));
      expect(ownerAcquireStart, greaterThan(acquisitionOwnerStart));
      expect(ownerAcquireEnd, greaterThan(ownerAcquireStart));
      final ownerAcquireSource = productionSource.substring(
        ownerAcquireStart,
        ownerAcquireEnd,
      );
      expect(
        ownerAcquireSource,
        contains('if (_acquisitionInFlight != null ||'),
      );
      expect(ownerAcquireSource, contains('_cleanupInFlight != null'));
      expect(
        ownerAcquireSource,
        contains('_emergencyCleanupInFlight != null'),
        reason: 'a successor cannot enter a predecessor cleanup generation',
      );
      expect(
        ownerAcquireSource,
        contains('Future<ProductionHeadlessOwnedRecoverySession?>.value(null)'),
        reason: 'a concurrent invocation must retry, never share one session',
      );
      expect(
        ownerAcquireSource,
        isNot(contains('return current;')),
        reason: 'a mutable owned session future cannot have two consumers',
      );
      final androidBackendStart = productionSource.indexOf(
        'final class AndroidProductionHeadlessCanonicalRecoveryBackend',
      );
      expect(androidBackendStart, greaterThan(ownerAcquireEnd));
      expect(
        productionSource.substring(androidBackendStart),
        contains('_acquisitionOwner.acquireSession('),
        reason: 'Android must delegate to the production-used shared owner',
      );
    },
  );

  test(
    'TC-374-06 concurrent foreground headless contenders share one owner and hand off newer work without loss',
    () async {
      final harness = _FactoryHarness();
      final first = harness.owner.acquireSession(
        binding: _binding,
        reason: CanonicalRecoveryReason.deletedBatch,
      );
      final contender = harness.owner.acquireSession(
        binding: _binding,
        reason: CanonicalRecoveryReason.periodicSweep,
      );
      final sessions = await Future.wait([first, contender]);
      expect(
        sessions.whereType<ProductionHeadlessOwnedRecoverySession>(),
        hasLength(1),
      );
      expect(harness.leaseAcquireCalls, 1);
      expect(harness.buildCount, 1);

      final owner = sessions
          .whereType<ProductionHeadlessOwnedRecoverySession>()
          .single;
      final cleanup = await owner.emergencyCleanup();
      expect(cleanup.databaseClosed, isTrue);
      expect(cleanup.leaseReleased, isTrue);

      harness.authority = _authority(
        marker: const CanonicalRecoveryMarker(generation: 8, binding: _binding),
      );
      final successor = await harness.owner.acquireSession(
        binding: _binding,
        reason: CanonicalRecoveryReason.deletedBatch,
      );
      expect(successor, isNotNull, reason: 'newer durable work must rerun');
      expect(harness.leaseAcquireCalls, 2);
      expect(harness.buildCount, 2);
      await successor!.emergencyCleanup();

      final releaseBoundaryHarness = _FactoryHarness(
        holdFirstReleaseAtBoundary: true,
      );
      expect(
        await releaseBoundaryHarness.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.deletedBatch,
          expectedMarker: _marker,
        ),
        isNotNull,
      );
      final predecessorCleanup = releaseBoundaryHarness.owner
          .emergencyCleanup();
      await _waitUntil(
        () => releaseBoundaryHarness.trace.contains('release:true'),
      );
      final firstReleaseFuture = releaseBoundaryHarness.firstReleaseFuture!;
      late Future<ProductionHeadlessOwnedRecoverySession?> boundaryAcquire;
      late Future<HeadlessCanonicalRecoveryCleanup> boundaryEmergencyCleanup;
      final boundaryInterleave = firstReleaseFuture.then((_) {
        expect(
          releaseBoundaryHarness.leaseOwned,
          isFalse,
          reason: 'the predecessor native lease has just released',
        );
        boundaryAcquire = releaseBoundaryHarness.owner.acquireSession(
          binding: _binding,
          reason: CanonicalRecoveryReason.periodicSweep,
        );
        boundaryEmergencyCleanup = releaseBoundaryHarness.owner
            .emergencyCleanup();
        expect(
          identical(boundaryEmergencyCleanup, predecessorCleanup),
          isTrue,
          reason: 'cleanup calls coalesce only while no successor may enter',
        );
      });
      releaseBoundaryHarness.firstReleaseCompleter!.complete(true);
      await boundaryInterleave;
      expect(
        await boundaryAcquire,
        isNull,
        reason: 'a successor cannot enter the predecessor cleanup generation',
      );
      final predecessorFacts = await predecessorCleanup;
      expect(predecessorFacts.databaseClosed, isTrue);
      expect(predecessorFacts.leaseReleased, isTrue);
      final boundarySuccessor = await releaseBoundaryHarness.owner
          .acquireSession(
            binding: _binding,
            reason: CanonicalRecoveryReason.periodicSweep,
          );
      expect(
        boundarySuccessor,
        isNotNull,
        reason: 'the successor enters after the cleanup future retires',
      );
      expect(releaseBoundaryHarness.leaseAcquireCalls, 2);
      await releaseBoundaryHarness.owner.emergencyCleanup();

      final runnerHarness = _FactoryHarness();
      final runner = ProductionHeadlessCanonicalRecoveryRunner(
        backend: runnerHarness.owner,
      );
      final firstRun = runner.run(
        invocation: const HeadlessCanonicalRecoveryInvocation(
          reason: CanonicalRecoveryReason.deletedBatch,
          nativeReason: 'deleted_batch',
          nonce: 'first',
          binding: _binding,
          generation: 7,
        ),
        isStopRequested: () => false,
      );
      final conflictingRun = await runner.run(
        invocation: const HeadlessCanonicalRecoveryInvocation(
          reason: CanonicalRecoveryReason.periodicSweep,
          nativeReason: 'periodic_sweep',
          nonce: 'contender',
          binding: _binding,
          generation: null,
        ),
        isStopRequested: () => false,
      );
      expect(
        conflictingRun.result.disposition,
        CanonicalRecoveryDisposition.retry,
      );
      expect(
        conflictingRun.result.failureReason,
        'headless_recovery_already_in_flight',
        reason: 'different invocations may never share one mutable run result',
      );
      expect(
        (await firstRun).result.disposition,
        CanonicalRecoveryDisposition.succeeded,
      );
      expect(runnerHarness.leaseAcquireCalls, 1);
      expect(runnerHarness.buildCount, 1);
    },
  );
}

ProductionHeadlessCanonicalAuthoritySnapshot _authority({
  CanonicalRecoveryMarker? marker = _marker,
  bool recoveryWorkEnabled = true,
}) => ProductionHeadlessCanonicalAuthoritySnapshot(
  binding: _binding,
  marker: marker,
  recoveryWorkEnabled: recoveryWorkEnabled,
  migrationAllowsRecovery: true,
  roleAllowsRecovery: true,
  authorityFingerprint: 'primary:account-peer',
);

ProductionHeadlessRecoverySessionDelegates _sessionDelegates({
  required List<String> trace,
  required ProductionHeadlessRecoveryAdmissionBarrier barrier,
  Completer<void>? quiesceRelease,
  String? failAt,
  int externalSealFailures = 0,
}) {
  var remainingExternalSealFailures = externalSealFailures;
  return ProductionHeadlessRecoverySessionDelegates(
    ensureRuntimeReady: () async => trace.add('runtime'),
    ensureTransportHealthy: () async => trace.add('transport'),
    drainDirectInbox: () async {
      trace.add('direct');
      return const CanonicalRecoveryDrainOutcome(
        isSuccessful: true,
        hasMore: false,
      );
    },
    drainGroupInbox: () async {
      trace.add('group');
      return const CanonicalRecoveryDrainOutcome(
        isSuccessful: true,
        hasMore: false,
      );
    },
    settleNotificationProjection: ({required authoritative}) async {
      trace.add('settle:${authoritative ? 'authoritative' : 'preliminary'}');
      return const CanonicalRecoveryProjectionOutcome(
        isSuccessful: true,
        hasPendingWork: false,
      );
    },
    sealExternalAdmission: () {
      trace.add('seal:external');
      if (remainingExternalSealFailures > 0) {
        remainingExternalSealFailures--;
        throw StateError('one-shot seal failure');
      }
      if (failAt == 'seal') throw StateError('seal failed');
    },
    awaitExternalInFlight: () async => trace.add('await:external'),
    stopGroupMessageListener: () async {
      trace.add('group:stop');
      if (failAt == 'groupStop') throw StateError('group stop failed');
    },
    disposeProjectionOwners: () async {
      trace.add('owners:dispose');
      if (failAt == 'dispose') throw StateError('owner dispose failed');
    },
    quiesceRuntime: () async {
      trace.add('go:quiesce');
      await quiesceRelease?.future;
      return true;
    },
    disposeRuntimeOwnersAfterNativeQuiescence: () async {
      trace.add('runtime-owners:dispose');
      await quiesceRelease?.future;
      return true;
    },
    admissionBarrier: barrier,
  );
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var i = 0; i < 1000; i++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition did not become true');
}

int _occurrences(String source, String token) =>
    token.allMatches(source).length;

File _repoFile(String relativePath) {
  for (final prefix in const <String>['', '../', '../../']) {
    final file = File('$prefix$relativePath');
    if (file.existsSync()) return file;
  }
  throw StateError('Cannot locate $relativePath');
}

final class _FactoryHarness {
  _FactoryHarness({
    ProductionHeadlessCanonicalAuthoritySnapshot? authority,
    this.qualifyIdentity = true,
    this.linked = false,
    this.authorityAfterQualification,
    this.constructionFailureProof,
    this.holdFirstReleaseAtBoundary = false,
    this.failOpenAfterHandle = false,
    this.closeDatabaseSucceeds = true,
  }) : authority = authority ?? _authority() {
    if (holdFirstReleaseAtBoundary) {
      final completer = Completer<bool>();
      firstReleaseCompleter = completer;
      firstReleaseFuture = completer.future.then((released) {
        if (released) leaseOwned = false;
        return released;
      });
    }
    owner = ProductionHeadlessCanonicalRecoveryAcquisitionOwner<Object, bool>(
      loadAuthority: () async => this.authority,
      hasWritableOwnership: () => leaseOwned,
      acquireThenOpen:
          ({
            required binding,
            required openDatabase,
            required closeAfterOpenFailure,
            required closeDatabaseOnRuntimeAttachFailure,
          }) async {
            if (leaseOwned) throw StateError('fake lease already owned');
            leaseAcquireCalls++;
            leaseOwned = true;
            trace.add('lease:$binding');
            return openDatabase();
          },
      openExistingDatabase: ({required onOpened}) async {
        trace.add('open-existing-v116');
        database = Object();
        onOpened(database!);
        if (failOpenAfterHandle) {
          throw StateError('injected post-open finalization failure');
        }
        return database!;
      },
      qualifyDatabase:
          ({required database, required binding, required preflight}) async {
            trace.add('passive-identity');
            trace.add('qualify:$qualifyIdentity');
            if (!qualifyIdentity) return null;
            qualifiedPhysicalPeerId = linked
                ? 'linked-physical-peer'
                : 'account-peer';
            final qualified = ProductionHeadlessCanonicalRecoveryQualification(
              identity: ProductionHeadlessQualifiedIdentity(
                accountPeerId: 'account-peer',
                physicalPeerId: qualifiedPhysicalPeerId!,
                physicalPrivateKey: linked
                    ? 'linked-private'
                    : 'account-private',
                binding: binding,
                authorityFingerprint: preflight.authorityFingerprint!,
                isLinked: linked,
              ),
              context: linked,
            );
            final replacementAuthority = authorityAfterQualification;
            if (replacementAuthority != null) {
              this.authority = replacementAuthority;
            }
            return qualified;
          },
      buildSession:
          ({required database, required qualification, required reason}) async {
            buildCount++;
            goOrNetworkEffectCount++;
            trace.add(
              'build:${qualification.identity.isLinked ? 'linked' : 'primary'}',
            );
            final cleanupProof = constructionFailureProof;
            if (cleanupProof != null) {
              throw ProductionCanonicalRecoveryCompositionConstructionFailure(
                cause: StateError('injected construction failure'),
                causeStackTrace: StackTrace.current,
                cleanupProof: cleanupProof,
              );
            }
            return _sessionDelegates(
              trace: trace,
              barrier: ProductionHeadlessRecoveryAdmissionBarrier(),
            );
          },
      closeDatabase: (database) async {
        trace.add('close-database');
        return closeDatabaseSucceeds;
      },
      beginOwnershipDrain: () async {
        trace.add('native:begin-drain');
        return true;
      },
      awaitOwnershipQuiescence: () async {
        trace.add('native:await-quiescence');
        return true;
      },
      releaseOwnership: ({required databaseClosed}) {
        trace.add('release:$databaseClosed');
        releaseCalls++;
        if (!databaseClosed) return Future<bool>.value(false);
        final heldRelease = firstReleaseFuture;
        if (releaseCalls == 1 && heldRelease != null) return heldRelease;
        leaseOwned = false;
        return Future<bool>.value(true);
      },
      acknowledgeHeadlessMarker: (marker, {authorityRevision}) async {
        trace.add('ack:${marker.generation}');
        return true;
      },
    );
  }

  ProductionHeadlessCanonicalAuthoritySnapshot authority;
  final bool qualifyIdentity;
  final bool linked;
  final ProductionHeadlessCanonicalAuthoritySnapshot?
  authorityAfterQualification;
  final ProductionCanonicalRecoveryConstructionCleanupProof?
  constructionFailureProof;
  final bool holdFirstReleaseAtBoundary;
  final bool failOpenAfterHandle;
  final bool closeDatabaseSucceeds;
  final List<String> trace = <String>[];
  late final ProductionHeadlessCanonicalRecoveryAcquisitionOwner<Object, bool>
  owner;
  Object? database;
  bool leaseOwned = false;
  int leaseAcquireCalls = 0;
  int buildCount = 0;
  int goOrNetworkEffectCount = 0;
  int releaseCalls = 0;
  Completer<bool>? firstReleaseCompleter;
  Future<bool>? firstReleaseFuture;
  String? qualifiedPhysicalPeerId;
}

final class _NativeGatewayOwnerHarness {
  _NativeGatewayOwnerHarness() {
    gateway = _TracingCanonicalRuntimeLeaseGateway(trace);
    writableSession = CanonicalWritableRuntimeSession(gateway: gateway);
    owner = ProductionHeadlessCanonicalRecoveryAcquisitionOwner<Object, bool>(
      loadAuthority: () async => _authority(),
      hasWritableOwnership: () => writableSession.hasWritableLease,
      acquireThenOpen:
          ({
            required binding,
            required openDatabase,
            required closeAfterOpenFailure,
            required closeDatabaseOnRuntimeAttachFailure,
          }) => writableSession.acquireThenOpen<Object>(
            binding: binding,
            openDatabase: openDatabase,
            closeAfterOpenFailure: closeAfterOpenFailure,
            closeDatabaseOnRuntimeAttachFailure:
                closeDatabaseOnRuntimeAttachFailure,
          ),
      openExistingDatabase: ({required onOpened}) async {
        trace.add('database:open');
        final database = Object();
        onOpened(database);
        return database;
      },
      qualifyDatabase:
          ({required database, required binding, required preflight}) async {
            return ProductionHeadlessCanonicalRecoveryQualification(
              identity: ProductionHeadlessQualifiedIdentity(
                accountPeerId: 'account-peer',
                physicalPeerId: 'account-peer',
                physicalPrivateKey: 'account-private',
                binding: binding,
                authorityFingerprint: preflight.authorityFingerprint!,
                isLinked: false,
              ),
              context: false,
            );
          },
      buildSession:
          ({required database, required qualification, required reason}) async {
            trace.add('build:primary');
            return _sessionDelegates(
              trace: trace,
              barrier: ProductionHeadlessRecoveryAdmissionBarrier(),
            );
          },
      closeDatabase: (database) async {
        trace.add('database:close');
        return true;
      },
      beginOwnershipDrain: writableSession.beginDrain,
      awaitOwnershipQuiescence: writableSession.awaitRuntimeQuiescence,
      releaseOwnership: ({required databaseClosed}) => writableSession
          .releaseAfterDatabaseClose(databaseClosed: databaseClosed),
      acknowledgeHeadlessMarker: (_, {authorityRevision}) async => true,
    );
  }

  final List<String> trace = <String>[];
  late final _TracingCanonicalRuntimeLeaseGateway gateway;
  late final CanonicalWritableRuntimeSession writableSession;
  late final ProductionHeadlessCanonicalRecoveryAcquisitionOwner<Object, bool>
  owner;
}

final class _TracingCanonicalRuntimeLeaseGateway
    implements CanonicalRuntimeLeaseGateway {
  _TracingCanonicalRuntimeLeaseGateway(this.trace);

  final List<String> trace;
  CanonicalRuntimeLeaseState _state = CanonicalRuntimeLeaseState.released;
  String? _binding;
  int _generation = 0;

  @override
  Future<CanonicalRuntimeLeaseSnapshot> acquire(String binding) async {
    trace.add('native:lease-acquire');
    if (_state != CanonicalRuntimeLeaseState.released) {
      throw StateError('native writable lease is already owned');
    }
    _state = CanonicalRuntimeLeaseState.active;
    _binding = binding;
    _generation++;
    return _snapshot();
  }

  @override
  Future<bool> attachRuntime() async {
    trace.add('native:runtime-attach');
    return _state == CanonicalRuntimeLeaseState.active;
  }

  @override
  Future<bool> beginDrain() async {
    trace.add('native:begin-drain');
    if (_state == CanonicalRuntimeLeaseState.active) {
      _state = CanonicalRuntimeLeaseState.draining;
    }
    return _state == CanonicalRuntimeLeaseState.draining;
  }

  @override
  Future<bool> quiesceRuntime() async {
    trace.add('native:host-stop-and-quiesce');
    return _state == CanonicalRuntimeLeaseState.draining;
  }

  @override
  Future<bool> release({required bool databaseClosed}) async {
    trace.add('native:lease-release:$databaseClosed');
    if (_state != CanonicalRuntimeLeaseState.draining || !databaseClosed) {
      return false;
    }
    _state = CanonicalRuntimeLeaseState.released;
    _binding = null;
    return true;
  }

  @override
  Future<CanonicalRuntimeLeaseSnapshot> rebind(String binding) async {
    if (_state != CanonicalRuntimeLeaseState.active) {
      throw StateError('only the active owner may rebind');
    }
    _binding = binding;
    return _snapshot();
  }

  @override
  Future<CanonicalRuntimeLeaseSnapshot> status() async => _snapshot();

  CanonicalRuntimeLeaseSnapshot _snapshot() => CanonicalRuntimeLeaseSnapshot(
    state: _state,
    generation: _state == CanonicalRuntimeLeaseState.released
        ? null
        : _generation,
    binding: _binding,
    role: _state == CanonicalRuntimeLeaseState.released ? null : 'RECOVERY',
    maximumConcurrentWritableOwners:
        _state == CanonicalRuntimeLeaseState.released ? 0 : 1,
  );
}

final class _HeadlessBackgroundVisibility
    extends AppVisibilitySuppressionReader {
  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async => const AppVisibilityEvaluation(
    isForegroundActive: false,
    maySuppress: false,
    lifecycle: AppVisibilityLifecycle.background,
    revision: 1,
    lifecycleGeneration: 1,
  );
}

final class _Tc37504Session implements CanonicalRecoverySession {
  _Tc37504Session({required this.drainDirect, required this.settle});

  final Future<CanonicalRecoveryDrainOutcome> Function() drainDirect;
  final Future<CanonicalRecoveryProjectionOutcome> Function() settle;

  @override
  Future<void> ensureRuntimeReady() async {}

  @override
  Future<void> ensureTransportHealthy() async {}

  @override
  Future<CanonicalRecoveryDrainOutcome> drainDirectInbox() => drainDirect();

  @override
  Future<CanonicalRecoveryDrainOutcome> drainGroupInbox() async =>
      const CanonicalRecoveryDrainOutcome(isSuccessful: true, hasMore: false);

  @override
  Future<CanonicalRecoveryProjectionOutcome> settleNotificationProjection() =>
      settle();

  @override
  Future<void> sealAdmissionAndAwaitInFlight() async {}

  @override
  Future<void> stopGroupMessageListener() async {}

  @override
  Future<void> disposeProjectionOwners() async {}

  @override
  Future<bool> quiesceRuntime() async => true;

  @override
  Future<bool> closeDatabase() async => true;

  @override
  Future<bool> releaseOwnership({required bool databaseClosed}) async => true;
}
