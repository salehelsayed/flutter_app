import 'dart:async';
import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/database/db_write_transaction.dart';
import '../../../core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import '../../../core/secure_storage/secure_key_store.dart';
import '../../identity/domain/models/identity_model.dart';
import '../application/call_history_projector.dart';
import '../application/call_signaling_context_store.dart';
import '../data/call_history_repository.dart';
import '../data/call_history_repository_impl.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';

const activeCallHistoryCheckpointKey = 'vc2_active_call_history_v1';

/// One authenticated history checkpoint, never signaling or media recovery.
final class ActiveCallHistoryCheckpoint {
  ActiveCallHistoryCheckpoint({
    required this.database,
    required this.secureKeyStore,
    required this.localIdentity,
    required this.readContext,
    required this.clock,
    this.onTerminalProjected,
  });

  final Database database;
  final SecureKeyStore secureKeyStore;
  final IdentityModel localIdentity;
  final CallSignalingContext? Function(CallId) readContext;
  final DateTime Function() clock;
  final void Function(CallHistoryEntry entry, bool inserted)?
  onTerminalProjected;
  Future<bool>? _availability;

  // Old terminal projections may finish after a graph replacement. Serialize
  // the shared key's compare/delete with successor writes as well.
  static final _tails = Expando<Future<void>>();

  Future<T> _mutate<T>(Future<T> Function() action) {
    final next = (_tails[secureKeyStore] ?? Future<void>.value()).then<T>(
      (_) => action(),
    );
    _tails[secureKeyStore] = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  Future<bool> _available() => _availability ??= _readAvailability();

  Future<bool> _readAvailability() async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
      "('identity', 'contact_relationship_consent', 'call_history', "
      "'direct_contact_device_bindings', 'direct_contact_device_roster_metadata')",
    );
    return tables.length == 5;
  }

  Future<void> save(CallSessionSnapshot snapshot) => _mutate(() async {
    if (snapshot.isTerminal ||
        snapshot.callId == null ||
        snapshot.startedAt == null ||
        snapshot.direction == null ||
        (snapshot.direction == CallDirection.incoming &&
            !snapshot.incomingValidated)) {
      return;
    }
    final context = readContext(snapshot.callId!);
    if (context == null) return; // Outgoing preparation has not bound a handle.
    if (!await _available()) {
      return; // Legacy host fixtures have partial schemas.
    }
    if (context.localAccountPeerId != localIdentity.peerId ||
        context.remoteAccountPeerId != snapshot.contactPeerId) {
      throw StateError('call checkpoint binding changed');
    }
    final authority = await dbWriteTransaction(
      database,
      (tx) => _authority(
        tx,
        context.remoteAccountPeerId,
        context.remoteDevicePeerId,
      ),
    );
    final admissionAuthority = context.admissionAuthority;
    if (authority == null ||
        admissionAuthority == null ||
        authority['remote_fingerprint'] != admissionAuthority.fingerprint ||
        authority['relationship_revision'] !=
            admissionAuthority.relationshipRevision) {
      throw StateError('call checkpoint authority revoked');
    }
    final prior = await _read();
    var observedAt = snapshot.observedAt;
    if (prior != null) {
      if (prior['call_id'] != snapshot.callId!.value) {
        await _settle(prior);
      } else if (!_matchesAuthority(prior, authority) ||
          prior['call_handle'] != context.callHandle ||
          prior['contact'] != context.remoteAccountPeerId ||
          prior['remote_device'] != context.remoteDevicePeerId) {
        throw StateError('call checkpoint authority changed');
      } else {
        // A delayed state event cannot shorten a newer live observation.
        final priorObservation = DateTime.parse(
          prior['observed_at']! as String,
        );
        if (priorObservation.isAfter(observedAt)) {
          observedAt = priorObservation;
        }
      }
    }
    await secureKeyStore.write(
      activeCallHistoryCheckpointKey,
      jsonEncode({
        'version': 1,
        'call_id': snapshot.callId!.value,
        'call_handle': context.callHandle,
        'contact': context.remoteAccountPeerId,
        'remote_device': context.remoteDevicePeerId,
        ...authority,
        'direction': snapshot.direction!.name,
        'started_at': snapshot.startedAt!.toIso8601String(),
        'connected_at': snapshot.connectedAt?.toIso8601String(),
        'observed_at': observedAt.toIso8601String(),
      }),
    );
  });

  /// Runs before native attach and mailbox intake, even without a native journal.
  Future<void> recover() => _mutate(() async {
    final record = await _read();
    if (record == null) return;
    if (!await _available()) {
      throw StateError('call checkpoint authority schema unavailable');
    }
    await _settle(record);
  });

  Future<void> clear(CallId callId) => _mutate(() => _clear(callId.value));

  Future<void> _clear(String callId) async {
    final record = await _read();
    if (record?['call_id'] == callId) {
      await secureKeyStore.delete(activeCallHistoryCheckpointKey);
    }
  }

  Future<void> _settle(Map<String, Object?> record) async {
    (CallHistoryEntry, bool)? projected;
    await dbWriteTransaction(database, (tx) async {
      final authority = await _authority(
        tx,
        record['contact']! as String,
        record['remote_device']! as String,
      );
      // Revocation retires the local checkpoint without recreating history.
      if (authority == null || !_matchesAuthority(record, authority)) return;
      final direction = CallDirection.values.byName(
        record['direction']! as String,
      );
      final endedAt = DateTime.parse(record['observed_at']! as String);
      await CallHistoryProjector(
        CallHistoryRepositoryImpl(database, terminalExecutor: tx),
        clock: clock,
        onTerminalProjected: (entry, inserted) => projected = (entry, inserted),
      ).projectTerminal(
        CallSessionSnapshot.active(
          callId: CallId.parse(record['call_id']! as String),
          contactPeerId: record['contact']! as String,
          direction: direction,
          state: CallState.ended,
          callerAccountPeerId: direction == CallDirection.outgoing
              ? localIdentity.peerId
              : record['contact']! as String,
          callerDeviceId: direction == CallDirection.outgoing
              ? localIdentity.peerId
              : record['remote_device']! as String,
          startedAt: DateTime.parse(record['started_at']! as String),
          connectedAt: record['connected_at'] == null
              ? null
              : DateTime.parse(record['connected_at']! as String),
          observedAt: endedAt,
          endedAt: endedAt,
          endReason: CallEndReason.mediaFailed,
        ),
      );
    });
    final announcement = projected;
    if (announcement != null) {
      try {
        onTerminalProjected?.call(announcement.$1, announcement.$2);
      } catch (_) {
        // The row is committed; presentation cannot fail history custody.
      }
    }
    // The write (or authoritative revocation) committed before removing bytes.
    await _clear(record['call_id']! as String);
  }

  Future<Map<String, Object?>?> _authority(
    DatabaseExecutor tx,
    String contact,
    String remoteDevice,
  ) async {
    final identities = await tx.query(
      'identity',
      columns: ['peer_id', 'public_key', 'ml_kem_public_key'],
      where: 'id = 1',
      limit: 1,
    );
    if (identities.length != 1) return null;
    final identity = identities.single;
    if (identity['peer_id'] != localIdentity.peerId ||
        identity['public_key'] != localIdentity.publicKey ||
        identity['ml_kem_public_key'] != localIdentity.mlKemPublicKey) {
      return null;
    }
    final consents = await tx.query(
      'contact_relationship_consent',
      columns: ['state', 'revision'],
      where: 'peer_id = ?',
      whereArgs: [contact],
      limit: 1,
    );
    if (consents.length != 1 ||
        consents.single['state'] != 'active' ||
        consents.single['revision'] is! int) {
      return null;
    }
    final roster = await dbReadDirectContactFanoutSnapshot(
      tx,
      contactAccountPeerId: contact,
    );
    if (roster == null) return null;
    final devices = roster.targets
        .where((target) => target.peerId == remoteDevice)
        .toList();
    if (devices.length != 1) return null;
    return {
      'local_fingerprint': computeDirectContactLegacyTargetFingerprint(
        contactAccountPeerId: localIdentity.peerId,
        accountSigningPublicKey: localIdentity.publicKey,
        legacyMlKemPublicKey: localIdentity.mlKemPublicKey!,
      ),
      'remote_fingerprint': devices.single.fingerprint,
      'relationship_revision': consents.single['revision'],
    };
  }

  bool _matchesAuthority(
    Map<String, Object?> record,
    Map<String, Object?> authority,
  ) => authority.keys.every((key) => record[key] == authority[key]);

  Future<Map<String, Object?>?> _read() async {
    final raw = await secureKeyStore.read(activeCallHistoryCheckpointKey);
    if (raw == null) return null;
    if (raw.length > 8192) {
      throw const FormatException('call checkpoint too large');
    }
    final record = Map<String, Object?>.from(jsonDecode(raw) as Map);
    const strings = [
      'call_id',
      'call_handle',
      'contact',
      'remote_device',
      'local_fingerprint',
      'remote_fingerprint',
      'direction',
      'started_at',
      'observed_at',
    ];
    if (record.length != 12 ||
        !record.containsKey('connected_at') ||
        record['version'] != 1 ||
        strings.any(
          (key) =>
              record[key] is! String ||
              (record[key]! as String).isEmpty ||
              (record[key]! as String).length > 512,
        ) ||
        record['relationship_revision'] is! int ||
        (record['relationship_revision']! as int) < 1 ||
        (record['connected_at'] != null && record['connected_at'] is! String)) {
      throw const FormatException('invalid call checkpoint');
    }
    CallId.parse(record['call_id']! as String);
    CallId.parse(record['call_handle']! as String);
    CallDirection.values.byName(record['direction']! as String);
    final started = DateTime.parse(record['started_at']! as String);
    final observed = DateTime.parse(record['observed_at']! as String);
    final connected = record['connected_at'] == null
        ? null
        : DateTime.parse(record['connected_at']! as String);
    if (observed.isBefore(started) ||
        (connected != null &&
            (connected.isBefore(started) || observed.isBefore(connected)))) {
      throw const FormatException('invalid call checkpoint chronology');
    }
    return record;
  }
}
