import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/app/bootstrap/android_production_audio_call_e2e_observer.dart';
import 'package:flutter_app/features/call/application/call_redial_controller.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_back_guard.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'production_journey_controller.dart';
import 'sims_runtime_protocol.dart';

/// The actual AppRoot callback handler supplies these read-only observations.
/// A controlled readiness wait exercises A/B supersession; native notification
/// actions, unlock, call admission and microphone permission remain real paths.
final class ProductionCallControls {
  ProductionCallControls._(this.journey) {
    if ({'kx0005', 'kx0006'}.contains(journey.invocation.scenarioId)) {
      _ready = Completer<bool>();
    }
    if (observesCallBack) {
      journey.bindAction('call_back.release_readiness', (_) async {
        if (_ready?.isCompleted == false) _ready!.complete(true);
        return {'released': true};
      });
      journey.bindAction('call_back.snapshot', (_) => snapshot());
    }
    journey.bindAction('call.snapshot', (_) => snapshot());
    if (observesDeadlines) {
      journey.bindAction('call.wire_deadlines', (_) async {
        if (_overflow) {
          throw StateError('Call wire/timer observation capacity exceeded.');
        }
        return {
          'encodedInvites': List<Map<String, Object?>>.of(_encodedInvites),
          'timers': List<Map<String, Object?>>.of(_timers),
        };
      });
    }
    if (journey.invocation.scenarioId == 'kx0029') {
      journey.bindAction('call.outputs', (_) async {
        final current = source;
        final session = current?.readCurrentSession();
        final read = current?.readOutputDevices;
        if (current == null ||
            read == null ||
            session?.callId == null ||
            session!.isIdle ||
            session.isTerminal) {
          throw StateError(
            'The actual active call output provider is unavailable.',
          );
        }
        final outputs = await read(session.callId!);
        final foreground = current.readCurrentForeground();
        if (current.readCurrentSession()?.callId != session.callId ||
            foreground?.session.callId != session.callId) {
          throw StateError(
            'The active call changed during output observation.',
          );
        }
        final audio = foreground!.audio;
        // Native endpoint identifiers and names remain ephemeral in the picker.
        return {
          'callSha256': sha256
              .convert(utf8.encode(session.callId!.value))
              .toString(),
          'audioActive': audio.active,
          'selectedRoute': audio.selectedRoute.name,
          'supportedRoutes':
              audio.supportedRoutes.map((route) => route.name).toList()..sort(),
          'outputs': [
            for (var i = 0; i < outputs.length; i++)
              {
                'index': i,
                'route': outputs[i].route.name,
                'selected': outputs[i].selected,
              },
          ],
        };
      });
    }
  }

  static ProductionCallControls? tryCreate(
    ProductionJourneyController? journey,
  ) =>
      journey != null &&
          journey.profileId == 'android.e2e.production_call_local' &&
          journey.invocation.role == 'alice' &&
          productionCallJourneys.contains(journey.invocation.scenarioId)
      ? ProductionCallControls._(journey)
      : null;

  final ProductionJourneyController journey;
  bool get observesDeadlines => journey.invocation.scenarioId == 'kx0001';
  bool get observesCallBack =>
      productionCallBackJourneys.contains(journey.invocation.scenarioId);
  Completer<bool>? _ready;
  AndroidProductionAudioCallObservationSource? source;
  final _events = <Map<String, Object?>>[];
  final _encodedInvites = <Map<String, Object?>>[];
  final _timers = <Map<String, Object?>>[];
  var _overflow = false;
  var _disposed = false;

  void observeEncoded(CallSignal signal, String signedEnvelope) {
    if (_disposed ||
        !observesDeadlines ||
        signal.event != CallSignalType.invite) {
      return;
    }
    if (_encodedInvites.length >= 64) {
      _overflow = true;
      return;
    }
    final outer = jsonDecode(signedEnvelope) as Map;
    _encodedInvites.add({
      'callSha256': sha256.convert(utf8.encode(signal.callId.value)).toString(),
      'wireSha256': sha256.convert(utf8.encode(signedEnvelope)).toString(),
      'messageSha256': sha256.convert(utf8.encode(signal.messageId)).toString(),
      'signaturePresent':
          outer['signature'] is String &&
          (outer['signature'] as String).isNotEmpty,
      'createdAtMs': signal.createdAtMs,
      'expiresAtMs': signal.expiresAtMs,
      'wireExpiresAtMs': outer['expires_at_ms'],
    });
  }

  void observeTimer(
    CallId callId,
    CallTimeoutKind kind,
    DateTime scheduledAt,
    Duration requestedDelay,
    Duration effectiveDelay,
  ) {
    if (_disposed ||
        !observesDeadlines ||
        !{
          CallTimeoutKind.noAnswer,
          CallTimeoutKind.inviteExpiry,
        }.contains(kind)) {
      return;
    }
    if (_timers.length >= 64) {
      _overflow = true;
      return;
    }
    final session = source?.readCurrentSession();
    _timers.add({
      'callSha256': sha256.convert(utf8.encode(callId.value)).toString(),
      'kind': kind.name,
      'scheduledAtMs': scheduledAt.millisecondsSinceEpoch,
      'requestedDelayMs': requestedDelay.inMilliseconds,
      'effectiveDelayMs': effectiveDelay.inMilliseconds,
      'deadlineMs': scheduledAt.add(effectiveDelay).millisecondsSinceEpoch,
      if (session?.callId == callId)
        'callStartedAtMs': session?.startedAt?.millisecondsSinceEpoch,
    });
  }

  static const historyA = '42000000-0000-4000-8000-0000000000a1';
  static const historyB = '42000000-0000-4000-8000-0000000000b2';

  /// Fixture data and real native cards only. These commands cannot submit a
  /// callback or start a call; the host must use the native notification action.
  void bindFixture({
    required Database database,
    required ContactRepository contacts,
    required NotificationService? notifications,
    Future<bool> Function()? readAlwaysRelay,
  }) {
    if (journey.invocation.scenarioId == 'kx0030') {
      final read =
          readAlwaysRelay ??
          (throw StateError('The preference reader is required.'));
      journey.bindAction(
        'call.always_relay_preference',
        (_) async => {'alwaysRelay': await read()},
      );
    }
    journey.bindAction('call.peer_name', (arguments) async {
      final peer = arguments['peerId'];
      if (peer is! String || peer.isEmpty) {
        throw StateError('A fixture peer is required.');
      }
      final contact = await contacts.getContact(peer);
      if (contact == null) {
        throw StateError('The authenticated fixture contact is absent.');
      }
      final name = contact.username.trim();
      return {
        'contactSha256': sha256.convert(utf8.encode(peer)).toString(),
        'displayNameSha256': sha256.convert(utf8.encode(name)).toString(),
        'readableName': name.isNotEmpty && name.length <= 128 && name != peer,
        'blocked': contact.isBlocked,
      };
    });
    if (journey.invocation.scenarioId == 'kx0017') {
      journey.bindAction('call_name.peer_id_username', (arguments) async {
        final peer = arguments['peerId'];
        if (peer is! String || peer.isEmpty) {
          throw StateError('An existing fixture peer is required.');
        }
        return dbWriteTransaction(database, (transaction) async {
          final before = await transaction.query(
            'contacts',
            where: 'peer_id = ?',
            whereArgs: [peer],
          );
          if (before.length != 1) {
            throw StateError('The authenticated fixture contact is absent.');
          }
          String otherColumns(Map<String, Object?> row) {
            final keys = row.keys.where((key) => key != 'username').toList()
              ..sort();
            return sha256
                .convert(
                  utf8.encode(
                    jsonEncode({for (final key in keys) key: row[key]}),
                  ),
                )
                .toString();
          }

          final count = await transaction.update(
            'contacts',
            {'username': peer},
            where: 'peer_id = ?',
            whereArgs: [peer],
          );
          final after = await transaction.query(
            'contacts',
            where: 'peer_id = ?',
            whereArgs: [peer],
          );
          if (count != 1 || after.length != 1) {
            throw StateError('Fixture contact update was not exact.');
          }
          return {
            'peerSha256': sha256.convert(utf8.encode(peer)).toString(),
            'beforeOtherColumnsSha256': otherColumns(before.single),
            'afterOtherColumnsSha256': otherColumns(after.single),
            'afterUsernameEqualsPeerId': after.single['username'] == peer,
          };
        });
      });
    }
    if (!observesCallBack) return;
    final notifier =
        notifications ??
        (throw StateError('The production notification service is required.'));
    final peerA = 'fixture-callback-a-${journey.invocation.runId}';
    Future<Map<String, Object?>> card(String id) async {
      final rows = await database.query(
        'call_history',
        where: 'call_id = ?',
        whereArgs: [id],
      );
      if (rows.length != 1) throw StateError('Missing owned callback history.');
      final peer = rows.single['contact_account_peer_id'] as String;
      final contact = await contacts.getContact(peer);
      if (contact == null || contact.isBlocked) {
        throw StateError('Callback fixture contact unavailable.');
      }
      await notifier.showMissedCallNotification(
        contactAccountPeerId: peer,
        title: contact.username,
        body: 'Missed call',
        callId: id,
      );
      return {
        'title': contact.username,
        'historyCallSha256': sha256.convert(utf8.encode(id)).toString(),
        'contactSha256': sha256.convert(utf8.encode(peer)).toString(),
      };
    }

    journey.bindAction('call_back.seed', (arguments) async {
      final dual = {'kx0005', 'kx0006'}.contains(journey.invocation.scenarioId);
      final peerB = arguments['peerB'];
      if (peerB is! String ||
          peerB.isEmpty ||
          peerB == peerA ||
          await contacts.getContact(peerB) == null ||
          await contacts.getContact(peerA) != null) {
        throw StateError(
          'A fresh owned fixture and existing authenticated B are required.',
        );
      }
      final now = DateTime.now().toUtc();
      final start = now.toIso8601String();
      final end = now.add(const Duration(milliseconds: 1)).toIso8601String();
      if (dual) {
        await contacts.addContact(
          ContactModel(
            peerId: peerA,
            publicKey: 'fixture-only',
            rendezvous:
                '/mknoon/production-journey/${journey.invocation.runId}',
            username:
                'CallbackA${sha256.convert(utf8.encode(journey.invocation.runId)).toString().substring(0, 8)}',
            signature: 'fixture-only',
            scannedAt: start,
          ),
        );
      }
      for (final (id, peer) in [
        if (dual) (historyA, peerA),
        (historyB, peerB),
      ]) {
        await database.insert('call_history', {
          'call_id': id,
          'contact_account_peer_id': peer,
          'direction': 'incoming',
          'terminal_reason': 'no_answer',
          'status': 'missed',
          'started_at': start,
          'ended_at': end,
          'created_at': end,
          'updated_at': end,
        });
      }
      final posted = await card(dual ? historyA : historyB);
      return {
        'posted': posted,
        'b': {
          'historyCallSha256': sha256.convert(utf8.encode(historyB)).toString(),
          'contactSha256': sha256.convert(utf8.encode(peerB)).toString(),
        },
      };
    });
    journey.bindAction('call_back.post_b', (_) => card(historyB));
  }

  Future<bool> awaitReadiness() async =>
      !_disposed &&
      (await (_ready?.future ?? Future.value(true))) &&
      !_disposed;

  void observe(
    CallBackActionObservation event,
    CallId id,
    OutgoingCallStartResult? result,
  ) {
    if (_disposed) return;
    if (_events.length >= 64) {
      _overflow = true;
      return;
    }
    _events.add({
      'stage': event.name,
      'historyCallSha256': sha256.convert(utf8.encode(id.value)).toString(),
      if (result != null) 'result': result.name,
    });
  }

  Future<Map<String, Object?>> snapshot() async {
    if (_overflow) throw StateError('Callback observation capacity exceeded.');
    final current = source;
    final session = current?.readCurrentSession();
    CallConnectionSnapshot? connection;
    var connectionReadSucceeded = current != null;
    try {
      connection = await current?.readActiveConnectionSnapshot().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      connectionReadSucceeded = false;
    }
    final deviceUnlocked = await foregroundCallTaskChannel
        .invokeMethod<bool>('isDeviceUnlocked')
        .timeout(const Duration(seconds: 5));
    if (deviceUnlocked == null) {
      throw StateError('Native device lock state is unavailable.');
    }
    return {
      'events': List<Map<String, Object?>>.of(_events),
      'readinessHeld': _ready?.isCompleted == false,
      'sourceBound': current != null,
      'connectionReadSucceeded': connectionReadSucceeded,
      'deviceUnlocked': deviceUnlocked,
      if (session != null) ...{
        'state': session.state.name,
        'direction': session.direction?.name,
        'inCall': !session.isIdle && !session.isTerminal,
        if (session.callId != null)
          'callSha256': sha256
              .convert(utf8.encode(session.callId!.value))
              .toString(),
        if (session.contactPeerId != null)
          'contactSha256': sha256
              .convert(utf8.encode(session.contactPeerId!))
              .toString(),
      },
      if (connectionReadSucceeded) 'connectionPresent': connection != null,
      if (connection != null) ...{
        'localAudioEnabled': connection.localAudioEnabled,
        'inboundAudioRtpObserved': connection.inboundAudioRtpObserved,
        'outboundAudioRtpObserved': connection.outboundAudioRtpObserved,
      },
    };
  }

  void dispose() {
    _disposed = true;
    if (_ready?.isCompleted == false) _ready!.complete(false);
  }
}
