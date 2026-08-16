import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

const MethodChannel _plan374FixtureChannel = MethodChannel(
  'mknoon/headless_recovery_374_fixture',
);
const MethodChannel _plan374GoChannel = MethodChannel('com.mknoon/go_bridge');
const String _plan374DirectMessageId = 'plan374-direct-message';
const String _plan374GroupId = 'plan374-private-group';
const String _plan374GroupMessageId = 'plan374-group-message';

/// Debug-only seed/inspection helper. It never runs the recovery algorithm;
/// the measured owner is WorkManager's production headless entrypoint.
Future<void> runAndroidHeadlessRecovery374Fixture(
  List<String> arguments,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  final phase = arguments.isEmpty ? '' : arguments.first;
  final nonce = arguments.length < 2 ? '' : arguments[1];
  try {
    if (nonce.trim().isEmpty) throw StateError('missing fixture nonce');
    final facts = switch (phase) {
      'seed' => await _seedPlan374Custody(),
      'inspect' => await _inspectPlan374Recovery(),
      _ => throw StateError('unsupported fixture phase: $phase'),
    };
    await _plan374FixtureChannel.invokeMethod<void>('complete', {
      'phase': phase,
      'runNonce': nonce,
      ...facts,
    });
  } catch (error, stackTrace) {
    await _plan374FixtureChannel.invokeMethod<void>('failed', {
      'phase': phase,
      'runNonce': nonce,
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stack': stackTrace.toString(),
    });
  }
}

Future<Map<String, Object?>> _seedPlan374Custody() async {
  final secureKeyStore = FlutterSecureKeyStore();
  final droppedPushBridge = DroppedPushRecoveryBridge();
  final leaseGateway = MethodChannelCanonicalRuntimeLeaseGateway();
  final bindingCoordinator = CanonicalRuntimeBindingCoordinator(
    secureKeyStore: secureKeyStore,
    leaseGateway: leaseGateway,
    droppedPushBindingPublisher: droppedPushBridge,
    recoveryGraphRegistered: true,
  );
  final startup = await bindingCoordinator.loadStartupBinding();
  final writable = CanonicalWritableRuntimeSession(gateway: leaseGateway);
  Database? database;
  try {
    database = await writable.acquireThenOpen<Database>(
      binding: startup.leaseBinding,
      openDatabase: () => openEncryptedDatabase(
        secureKeyStore: secureKeyStore,
        dbName: 'identity.db',
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
      closeDatabaseOnRuntimeAttachFailure: (opened) async {
        await opened.close();
        return !opened.isOpen;
      },
    );

    final account = await _generateIdentity();
    final remote = await _generateIdentity();
    final mlKem = await _invokeGoJson('mlKemKeygen');
    if (mlKem['ok'] != true ||
        mlKem['publicKey'] is! String ||
        mlKem['secretKey'] is! String) {
      throw StateError('ML-KEM fixture generation failed');
    }
    await secureKeyStore.write(
      identityPrivateKeyStorageKey,
      account.privateKey,
    );
    await secureKeyStore.write(
      identityMnemonic12StorageKey,
      account.mnemonic12,
    );
    await secureKeyStore.write(
      identityMlKemSecretKeyStorageKey,
      mlKem['secretKey']! as String,
    );
    await dbUpsertIdentityRow(database, <String, Object?>{
      'peer_id': account.peerId,
      'public_key': account.publicKey,
      'private_key': null,
      'mnemonic12': null,
      'ml_kem_public_key': mlKem['publicKey']! as String,
      'ml_kem_secret_key': null,
      'username': 'Plan 374 Device Fixture',
      'avatar_path': null,
      'avatar_blob': null,
      'avatar_version': null,
      'created_at': account.createdAt,
      'updated_at': account.updatedAt,
    });

    final timestamp = DateTime.now().toUtc().toIso8601String();
    // This canonical insert deliberately enters the existing v107
    // `trg_direct_notification_reconcile_contact_insert` owner. The fixture
    // never writes a synthetic reconciliation table.
    await database.insert('contacts', <String, Object?>{
      'peer_id': remote.peerId,
      'public_key': remote.publicKey,
      'rendezvous': 'plan374-device-fixture',
      'username': 'Plan 374 Direct Peer',
      'signature': 'plan374-fixture-signature',
      'scanned_at': timestamp,
    });
    await database.insert('messages', <String, Object?>{
      'id': _plan374DirectMessageId,
      'contact_peer_id': remote.peerId,
      'sender_peer_id': remote.peerId,
      'text': 'Plan 374 direct recovery card',
      'timestamp': timestamp,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': timestamp,
    });
    final direct = DirectNotificationDisplayOutboxEntry.message(
      eventId: _plan374DirectMessageId,
      peerId: remote.peerId,
      messageId: _plan374DirectMessageId,
      actorPeerId: remote.peerId,
      eventTimestamp: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await dbStageDirectNotificationDisplayOutboxEntry(database, direct.toMap());
    if (!await dbPromoteDirectNotificationDisplayOutboxReadyIfExact(
      database,
      peerId: direct.peerId,
      eventKind: direct.eventKind,
      eventId: direct.eventId,
      expectedRevision: direct.revision,
      updatedAt: timestamp,
    )) {
      throw StateError('direct fixture custody did not become READY');
    }

    // This canonical insert likewise enters v106's
    // `trg_group_notification_reconcile_group_insert` owner.
    await database.insert('groups', <String, Object?>{
      'id': _plan374GroupId,
      'name': 'Plan 374 Private Group',
      'type': 'chat',
      'topic_name': 'plan374-private-group-topic',
      'description': 'device fixture',
      'created_at': timestamp,
      'created_by': account.peerId,
      'my_role': 'admin',
    });
    await database.insert('group_members', <String, Object?>{
      'group_id': _plan374GroupId,
      'peer_id': account.peerId,
      'username': 'Plan 374 Device Fixture',
      'role': 'admin',
      'public_key': account.publicKey,
      'ml_kem_public_key': mlKem['publicKey']! as String,
      'joined_at': timestamp,
    });
    await database.insert('group_members', <String, Object?>{
      'group_id': _plan374GroupId,
      'peer_id': remote.peerId,
      'username': 'Plan 374 Group Peer',
      'role': 'writer',
      'public_key': remote.publicKey,
      'joined_at': timestamp,
    });
    await database.insert('group_messages', <String, Object?>{
      'id': _plan374GroupMessageId,
      'group_id': _plan374GroupId,
      'sender_peer_id': remote.peerId,
      'sender_username': 'Plan 374 Group Peer',
      'text': 'Plan 374 group recovery card',
      'timestamp': timestamp,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': timestamp,
    });
    final group = GroupNotificationDisplayOutboxEntry.message(
      eventId: _plan374GroupMessageId,
      groupId: _plan374GroupId,
      messageId: _plan374GroupMessageId,
      actorPeerId: remote.peerId,
      eventTimestamp: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await dbStageGroupNotificationDisplayOutboxEntry(database, group.toMap());
    if (!await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
      database,
      eventId: group.eventId,
      expectedRevision: group.revision,
      updatedAt: timestamp,
    )) {
      throw StateError('group fixture custody did not become READY');
    }

    final binding = await bindingCoordinator.publishAccount(account.peerId);
    final registry =
        await DurableConversationNotificationIdRegistry.openMobileDefault();
    final initialized = await LocalNotificationLedgerStore(
      directory: registry.directory,
    ).initializeOrRebind(currentOpaqueBinding: binding);
    if (initialized == null || initialized.records.isNotEmpty) {
      throw StateError('Plan-372 ledger did not initialize empty');
    }

    final before = await _databaseFacts(database);
    if (before.values.any((value) => value < 1)) {
      throw StateError('fixture did not seed all four SQL custody stores');
    }
    final cipherVersion = await _pragmaValue(database, 'PRAGMA cipher_version');
    final userVersion = await _pragmaValue(database, 'PRAGMA user_version');
    await writable.drainCloseRelease(
      stopRuntime: () async {},
      closeDatabase: database.close,
    );
    return <String, Object?>{
      'databaseExistingBeforeRecovery': true,
      'databaseClosed': !database.isOpen,
      'databaseUserVersion': userVersion,
      'expectedDatabaseUserVersion': currentIdentityDatabaseVersion,
      'cipherVersion': cipherVersion,
      'binding': binding,
      'custodyBefore': before,
      'ledgerRecordsBefore': initialized.records.length,
    };
  } finally {
    if (database?.isOpen ?? false) await database!.close();
    droppedPushBridge.dispose();
  }
}

Future<Map<String, Object?>> _inspectPlan374Recovery() async {
  final secureKeyStore = FlutterSecureKeyStore();
  final storedKey = await secureKeyStore.read(dbEncryptionKeyStorageKey);
  final binding = await CanonicalRuntimeBindingCoordinator(
    secureKeyStore: secureKeyStore,
  ).readCurrentAccountBinding();
  if (storedKey == null || binding == null) {
    throw StateError('existing fixture authority is unavailable');
  }
  final databasePath = '${await getDatabasesPath()}/identity.db';
  final database = await openEncryptedDatabaseReadOnlyTolerant(
    path: databasePath,
    storedKey: storedKey,
  );
  late Map<String, Object?> facts;
  try {
    final identity = await dbLoadIdentityRow(database);
    final custody = await _databaseFacts(database);
    final registry =
        await DurableConversationNotificationIdRegistry.openMobileDefault();
    final ledger = await LocalNotificationLedgerStore(
      directory: registry.directory,
    ).read(currentOpaqueBinding: binding);
    if (ledger == null) throw StateError('Plan-372 ledger is unavailable');
    final records = ledger.records.values.toList(growable: false);
    facts = <String, Object?>{
      'databaseUserVersion': await _pragmaValue(
        database,
        'PRAGMA user_version',
      ),
      'expectedDatabaseUserVersion': currentIdentityDatabaseVersion,
      'cipherVersion': await _pragmaValue(database, 'PRAGMA cipher_version'),
      'quickCheck': await _pragmaValue(database, 'PRAGMA quick_check'),
      'identityPresent': identity != null,
      'custodyAfter': custody,
      'ledgerRecordCount': records.length,
      'ledgerClaimsSuspended': ledger.claimsSuspended,
      'ledgerRecords': records
          .map(
            (record) => <String, Object?>{
              'producerKind': record.producerKind.wireName,
              'sourceCustody': record.sourceCustody.wireName,
              'presentationOwner': record.presentationOwner.wireName,
              'presentationState': record.presentationState.wireName,
              'effectPhase': record.effectPhase.wireName,
              'notificationId': record.notificationId,
            },
          )
          .toList(growable: false),
      'settledSqlReadyInboxReconcilerCount': records
          .where(
            (record) =>
                record.sourceCustody ==
                    LocalNotificationSourceCustody.sqlReady &&
                record.presentationOwner ==
                    LocalNotificationPresentationOwner.inboxReconciler &&
                record.effectPhase == LocalNotificationEffectPhase.settled,
          )
          .length,
    };
  } finally {
    await database.close();
  }
  return <String, Object?>{...facts, 'databaseClosed': !database.isOpen};
}

Future<IdentityModel> _generateIdentity() async {
  final response = await _invokeGoJson('generateIdentity');
  final identity = response['identity'];
  if (response['ok'] != true || identity is! Map) {
    throw StateError('identity fixture generation failed');
  }
  return IdentityModel.fromJson(Map<String, dynamic>.from(identity));
}

Future<Map<String, dynamic>> _invokeGoJson(String method) async {
  final raw = await _plan374GoChannel.invokeMethod<String>(method);
  final decoded = raw == null ? null : jsonDecode(raw);
  if (decoded is! Map) throw StateError('$method returned malformed JSON');
  return Map<String, dynamic>.from(decoded);
}

Future<Map<String, int>> _databaseFacts(
  Database database,
) async => <String, int>{
  'directDisplay': await _count(database, 'direct_notification_display_outbox'),
  'directReconciliation': await _count(
    database,
    'direct_notification_reconciliation_outbox',
  ),
  'groupDisplay': await _count(database, 'group_notification_display_outbox'),
  'groupReconciliation': await _count(
    database,
    'group_notification_reconciliation_outbox',
  ),
};

Future<int> _count(Database database, String table) async =>
    Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM $table'),
    ) ??
    0;

Future<Object?> _pragmaValue(Database database, String pragma) async {
  final rows = await database.rawQuery(pragma);
  return rows.isEmpty || rows.first.values.isEmpty
      ? null
      : rows.first.values.first;
}
