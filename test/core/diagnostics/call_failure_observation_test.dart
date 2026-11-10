import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _id = CallId.parse('55555555-5555-4555-8555-555555555555');
final _now = DateTime.utc(2026, 11, 10);
CallEvent _event(CallEventType type) => CallEvent(
  type: type,
  eventId: type.name,
  occurredAt: _now,
  callId: _id,
  contactPeerId: 'PRIVATE_CALL_PEER',
  localAccountPeerId: 'PRIVATE_CALL_SELF',
  localDeviceId: 'PRIVATE_CALL_DEVICE',
  remoteAccountPeerId: 'PRIVATE_CALL_PEER',
  remoteDeviceId: 'PRIVATE_CALL_REMOTE_DEVICE',
);

final class _History implements CallHistoryRepository {
  final rows = <CallHistoryEntry>[];
  @override
  Future<void> upsertTerminal(CallHistoryEntry row) async {
    rows.add(row);
  }

  @override
  Future<CallHistoryEntry?> getByCallId(CallId id) async =>
      rows.where((r) => r.callId == id).firstOrNull;
  @override
  Future<List<CallHistoryEntry>> listForContact(String id) async => rows;
}

final class _Executor implements CallEffectExecutor {
  _Executor(this.target, this.error, {this.hang = false});
  final CallEffectType target;
  final Object error;
  final bool hang;
  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    if (effect.type == target) {
      if (hang) return Completer<CallEvent?>().future;
      throw error;
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CallDiagnostics diagnostics;
  late _History history;
  var cleanups = 0;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'call-failure-observation-',
    );
    diagnostics = await CallDiagnostics.installForTesting(directory: directory);
    history = _History();
    cleanups = 0;
  });
  tearDown(() async {
    await diagnostics.dispose();
    await directory.delete(recursive: true);
  });
  CallCoordinator coordinator({
    CallEffectExecutor? executor,
    Future<void> Function(CallSessionSnapshot)? persist,
  }) {
    final value = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator([
        CallCleanupStep('test_cleanup', (_) async {
          cleanups++;
        }),
      ]),
      historyProjector: CallHistoryProjector(history),
      effectExecutor: executor ?? const NoopCallEffectExecutor(),
      persistActiveCall: persist,
      clock: () => _now,
      idSource: () => _id,
      effectTimeout: const Duration(milliseconds: 20),
      mediaPreparationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(value.dispose);
    return value;
  }

  Future<List<Map<String, dynamic>>> records() async {
    final preview = await diagnostics.exportPreview();
    expect(preview, isNot(contains('PRIVATE_CALL')));
    return ((jsonDecode(preview) as Map)['events'] as List)
        .cast<Map<String, dynamic>>()
        .where((e) => e['action'] == 'finish')
        .toList();
  }

  Future<void> expectObservation({
    required bool media,
    required bool timeout,
  }) async {
    final events = await records();
    expect(events, hasLength(1));
    expect(events.single['stage'], media ? 'media' : 'runtime');
    expect(events.single['outcome'], timeout ? 'timeout' : 'failed');
    expect(
      events.single['reason'],
      timeout
          ? 'timeout'
          : media
          ? 'negotiation_failed'
          : 'unknown',
    );
    expect(events.single['values'], isEmpty);
  }

  void expectTerminal(CallCoordinator c, CallEndReason reason) {
    expect(c.activeSession, isNull);
    expect(c.lastSnapshot?.endReason, reason);
    expect(cleanups, 1);
    expect(history.rows, hasLength(1));
  }

  for (final target in [
    CallEffectType.startNegotiation,
    CallEffectType.prepareOutgoingInvite,
    CallEffectType.sendTerminate,
  ]) {
    for (final timeout in [false, true]) {
      test(
        '$target ${timeout ? 'timeout' : 'failure'} observes cause while preserving terminal behavior',
        () async {
          final error = timeout
              ? TimeoutException('PRIVATE_CALL_TIMEOUT')
              : StateError('PRIVATE_CALL_ERROR');
          final c = coordinator(executor: _Executor(target, error));
          if (target != CallEffectType.prepareOutgoingInvite) {
            await c.dispatch(_event(CallEventType.place));
          }
          if (target == CallEffectType.startNegotiation) {
            await c.dispatch(_event(CallEventType.outgoingInviteReady));
          }
          final trigger = target == CallEffectType.startNegotiation
              ? CallEventType.remoteAccept
              : target == CallEffectType.sendTerminate
              ? CallEventType.cancel
              : CallEventType.place;
          await expectLater(c.dispatch(_event(trigger)), throwsA(same(error)));
          expectTerminal(
            c,
            target == CallEffectType.startNegotiation
                ? CallEndReason.mediaFailed
                : target == CallEffectType.sendTerminate
                ? CallEndReason.callerCancelled
                : CallEndReason.signalingFailed,
          );
          await expectObservation(
            media: target == CallEffectType.startNegotiation,
            timeout: timeout,
          );
        },
      );
    }
  }
  for (final timeout in [false, true]) {
    test(
      'checkpoint ${timeout ? 'timeout' : 'failure'} is runtime with original exception preserved',
      () async {
        final error = timeout
            ? TimeoutException('PRIVATE_CALL_CHECKPOINT')
            : StateError('PRIVATE_CALL_CHECKPOINT');
        final c = coordinator(
          persist: (_) async {
            throw error;
          },
        );
        await expectLater(
          c.dispatch(_event(CallEventType.place)),
          throwsA(same(error)),
        );
        expectTerminal(c, CallEndReason.mediaFailed);
        await expectObservation(media: false, timeout: timeout);
      },
    );
  }
  test('actual negotiation budget expiry is a media timeout', () async {
    final c = coordinator(
      executor: _Executor(
        CallEffectType.startNegotiation,
        StateError('unused'),
        hang: true,
      ),
    );
    await c.dispatch(_event(CallEventType.place));
    await c.dispatch(_event(CallEventType.outgoingInviteReady));
    await expectLater(
      c.dispatch(_event(CallEventType.remoteAccept)),
      throwsA(isA<TimeoutException>()),
    );
    expectTerminal(c, CallEndReason.mediaFailed);
    await expectObservation(media: true, timeout: true);
  });
  test('actual checkpoint budget expiry is a runtime timeout', () async {
    final c = coordinator(persist: (_) => Completer<void>().future);
    await expectLater(
      c.dispatch(_event(CallEventType.place)),
      throwsA(isA<TimeoutException>()),
    );
    expectTerminal(c, CallEndReason.mediaFailed);
    await expectObservation(media: false, timeout: true);
  });
  for (final unavailable in [false, true]) {
    test(
      '${unavailable ? 'unavailable' : 'opted-out'} observer cannot change reducer cleanup history or exception',
      () async {
        if (unavailable) {
          var writes = 0;
          diagnostics = await CallDiagnostics.installForTesting(
            directory: directory,
            persist: (_, _) async {
              writes++;
              throw StateError('PRIVATE_CALL_OBSERVER');
            },
          );
          expect(writes, greaterThan(0));
        } else {
          await diagnostics.setEnabled(false);
        }
        final error = StateError('PRIVATE_CALL_ERROR');
        final c = coordinator(
          executor: _Executor(CallEffectType.startNegotiation, error),
        );
        await c.dispatch(_event(CallEventType.place));
        await c.dispatch(_event(CallEventType.outgoingInviteReady));
        await expectLater(
          c.dispatch(_event(CallEventType.remoteAccept)),
          throwsA(same(error)),
        );
        expectTerminal(c, CallEndReason.mediaFailed);
        final events = await records();
        if (!unavailable) expect(events, isEmpty);
      },
    );
  }
}
