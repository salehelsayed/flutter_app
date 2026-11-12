import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/call/application/call_control_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _call = CallId.parse('55555555-5555-4555-8555-555555555555');
final _other = CallId.parse('66666666-6666-4666-8666-666666666666');
const _handle = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _otherHandle = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
final _now = DateTime.utc(2026, 11, 12, 12);

CallSignalV2 _invite({
  bool incoming = false,
  CallId? callId,
  Map<String, Object?> overrides = const {},
}) => CallSignalV2.fromMap({
  'schema': CallSignalV2.schema,
  'call_id': (callId ?? _call).value,
  'message_id': '77777777-7777-4777-8777-777777777777',
  'event': 'invite',
  'sender_account_peer_id': incoming ? 'remote-account' : 'local-account',
  'sender_device_peer_id': incoming ? 'remote-device' : 'local-device',
  'recipient_account_peer_id': incoming ? 'local-account' : 'remote-account',
  'recipient_device_peer_id': incoming ? 'local-device' : 'remote-device',
  'sender_sequence': 7,
  'ice_generation': 2,
  'created_at_ms': _now.millisecondsSinceEpoch,
  'expires_at_ms': _now.add(const Duration(seconds: 40)).millisecondsSinceEpoch,
  'payload': {
    'media': 'video',
    'camera': 'off',
    'capabilities': ['audio', 'video'],
  },
  ...overrides,
}, videoEnabled: true);

CallSessionSnapshot _snapshot(
  CallState state, {
  bool incoming = false,
  CallId? callId,
  CallEndReason? reason,
}) => CallSessionSnapshot.active(
  callId: callId ?? _call,
  contactPeerId: 'remote-account',
  direction: incoming ? CallDirection.incoming : CallDirection.outgoing,
  state: state,
  callerAccountPeerId: incoming ? 'remote-account' : 'local-account',
  callerDeviceId: incoming ? 'remote-device' : 'local-device',
  startedAt: _now,
  observedAt: _now,
  acceptedAt: state == CallState.accepted ? _now : null,
  endedAt: state == CallState.ended ? _now : null,
  endReason: reason,
);

CallControlSendResult _receipt({
  bool stored = false,
  bool wake = false,
  Future<void>? settled,
}) => CallControlSendResult(
  directAccepted: !stored,
  mailboxStored: stored,
  wakeDispatched: wake,
  directRoute: stored ? null : CallRouteClass.direct,
  mailboxStoreSettled: settled ?? Future<void>.value(),
);

class _Port implements CallControlSignalingPort {
  _Port(this.invite);

  CallSignalV2? invite;
  Future<void> Function()? beforePrepare;
  final legacy = <CallSignal>[];
  int preparations = 0;

  @override
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  ) async {
    preparations++;
    await beforePrepare?.call();
    final prepared = invite;
    return prepared == null
        ? const OutgoingCallSignalingPreparation(
            callHandle: _handle,
            remoteAccountPeerId: 'remote-account',
            remoteDevicePeerId: 'remote-device',
            invitePayload: {
              'capabilities': ['audio'],
              'metadata': {'media': 'audio', 'video': false},
            },
          )
        : OutgoingCallSignalingPreparation.v2(
            callHandle: _handle,
            invite: prepared,
          );
  }

  @override
  Future<CallControlSendResult> send({
    required CallSignal signal,
    required String callHandle,
  }) async {
    legacy.add(signal);
    return _receipt();
  }
}

final class _V2Port extends _Port implements CallControlSignalingPortV2 {
  _V2Port(super.invite);

  final signals = <CallSignalV2>[];
  final handles = <String>[];
  Future<CallControlSendResult> Function(CallSignalV2 signal)? onSend;

  @override
  Future<CallControlSendResult> sendV2({
    required CallSignalV2 signal,
    required String callHandle,
  }) async {
    signals.add(signal);
    handles.add(callHandle);
    return onSend?.call(signal) ?? _receipt();
  }
}

final class _Harness {
  _Harness({
    bool enabled = true,
    bool typedPort = true,
    bool legacyInvite = false,
    CallSignalV2? invite,
  }) : port = typedPort
           ? _V2Port(legacyInvite ? null : invite ?? _invite())
           : _Port(legacyInvite ? null : invite ?? _invite()) {
    executor = CallControlEffectExecutor(
      contextStore: store,
      signalingPort: port,
      videoEnabled: enabled,
      clock: () => now,
      idSource: () => CallId.parse(
        '90000000-0000-4000-8000-${(++ids).toString().padLeft(12, '0')}',
      ),
      isOutgoingPreparationCurrent: (_) => current,
      registerOutgoingBeforeInvite: (callId) async {
        registrations++;
        return await onRegister?.call(callId) ?? true;
      },
      cancelOutgoingMailboxInvite:
          ({required recipientDevicePeerId, required callHandle}) async {
            cancelled.add((recipientDevicePeerId, callHandle));
            return true;
          },
    );
  }

  final store = CallSignalingContextStore(videoEnabled: true);
  final _Port port;
  late final CallControlEffectExecutor executor;
  DateTime now = _now;
  bool current = true;
  int ids = 0;
  int registrations = 0;
  Future<bool> Function(CallId)? onRegister;
  final cancelled = <(String, String)>[];
  _V2Port get v2 => port as _V2Port;

  Future<CallEvent?> prepare() => executor.execute(
    const CallEffect(CallEffectType.prepareOutgoingInvite),
    _snapshot(CallState.preparing),
  );

  Future<void> prepareV2() async {
    expect((await prepare())?.type, CallEventType.outgoingInviteReady);
    expect(store.read(_call)?.wireVersion, CallWireVersion.v2);
  }

  Future<CallEvent?> sendInvite() => executor.execute(
    const CallEffect(CallEffectType.sendInvite),
    _snapshot(CallState.inviting),
  );

  void incoming({CallId? callId, String handle = _handle}) {
    store.captureAuthenticatedV2(
      signal: _invite(incoming: true, callId: callId),
      callHandle: handle,
    );
  }
}

void main() {
  for (final enabled in [false, true]) {
    test('v1 control remains unchanged with video flag $enabled', () async {
      final h = _Harness(enabled: enabled, legacyInvite: true);
      expect((await h.prepare())?.type, CallEventType.outgoingInviteReady);
      expect(h.store.read(_call)?.wireVersion, CallWireVersion.v1);
      expect((await h.sendInvite())?.type, CallEventType.directAccepted);
      expect(h.registrations, 1);
      expect(h.port.legacy.single.payload, {
        'capabilities': ['audio'],
        'metadata': {'media': 'audio', 'video': false},
      });
      expect(h.port.legacy.single.senderSequence, 1);
      expect(h.v2.signals, isEmpty);
    });
  }

  test(
    'v2 context retains one exact immutable prepared invite until purge',
    () {
      final h = _Harness();
      final invite = _invite();
      h.store.storeOutgoingV2(invite: invite, callHandle: _handle);
      expect(h.store.read(_call)?.preparedOutgoingV2Invite, same(invite));
      expect(
        h.store.reserveNextMetadata(_call, iceGeneration: 2).senderSequence,
        8,
      );
      h.store.storeOutgoingV2(invite: _invite(), callHandle: _handle);
      expect(h.store.read(_call)?.preparedOutgoingV2Invite, same(invite));
      expect(h.store.read(_call)?.nextSenderSequence, 9);
      h.store.purge(_call);
      expect(h.store.read(_call), isNull);
      expect(h.store.length, 0);
    },
  );

  for (final drift in ['message', 'sequence', 'expiry', 'camera']) {
    test('v2 preparation cannot replace immutable invite $drift', () {
      final h = _Harness();
      final original = _invite();
      h.store.storeOutgoingV2(invite: original, callHandle: _handle);
      final changed = _invite(
        overrides: switch (drift) {
          'message' => {'message_id': _other.value},
          'sequence' => {'sender_sequence': 8},
          'expiry' => {
            'expires_at_ms': _now
                .add(const Duration(seconds: 39))
                .millisecondsSinceEpoch,
          },
          _ => {
            'payload': {
              'media': 'video',
              'camera': 'on',
              'capabilities': ['audio', 'video'],
            },
          },
        },
      );
      expect(
        () => h.store.storeOutgoingV2(invite: changed, callHandle: _handle),
        throwsA(
          isA<CallSignalingContextException>().having(
            (e) => e.code,
            'code',
            CallSignalingContextErrorCode.bindingConflict,
          ),
        ),
      );
      expect(h.store.read(_call)?.preparedOutgoingV2Invite, same(original));
      expect(h.store.read(_call)?.nextSenderSequence, 8);
    });
  }

  test(
    'v2 native registration sees immutable context before ready and send',
    () async {
      final h = _Harness();
      final order = <String>[];
      h.onRegister = (callId) async {
        expect(callId, _call);
        final context = h.store.read(callId);
        expect(context?.wireVersion, CallWireVersion.v2);
        expect(context?.preparedOutgoingV2Invite, same(h.port.invite));
        expect(context?.requestedMedia, CallMediaKind.video);
        expect(context?.callHandle, _handle);
        expect(h.v2.signals, isEmpty);
        order.add('register');
        return true;
      };
      await h.prepareV2();
      order.add('ready');
      expect((await h.sendInvite())?.type, CallEventType.directAccepted);
      order.add('send');
      expect(order, ['register', 'ready', 'send']);
      expect(h.v2.signals.single, same(h.port.invite));
      expect(h.v2.handles.single, _handle);
      expect(h.ids, 0, reason: 'the prepared invite already owns its identity');
      expect(h.store.read(_call)?.nextSenderSequence, 8);
      await h.sendInvite();
      expect(h.v2.signals, hasLength(1));
      expect(h.port.legacy, isEmpty);
    },
  );

  for (final boundary in ['flag', 'port']) {
    test('v2 outgoing refuses absent $boundary without v1 downgrade', () async {
      final h = _Harness(
        enabled: boundary != 'flag',
        typedPort: boundary != 'port',
      );
      final result = await h.prepare();
      expect(result?.type, CallEventType.negotiationFailed);
      expect(h.store.read(_call), isNull);
      expect(h.registrations, 0);
      expect(h.port.legacy, isEmpty);
    });
  }

  for (final field in [
    'call_id',
    'sender_account_peer_id',
    'sender_device_peer_id',
    'recipient_account_peer_id',
  ]) {
    test('v2 prepared invite must match canonical $field', () async {
      final invite = _invite(
        overrides: {field: field == 'call_id' ? _other.value : 'other-peer'},
      );
      final h = _Harness(invite: invite);
      expect((await h.prepare())?.type, CallEventType.negotiationFailed);
      expect(h.registrations, 0);
      expect(h.store.length, 0);
      expect(h.port.legacy, isEmpty);
      expect(h.v2.signals, isEmpty);
    });
  }

  for (final invalid in ['event', 'expired', 'future']) {
    test('v2 invalid prepared $invalid cannot register or send', () async {
      final h = _Harness(
        invite: _invite(
          overrides: switch (invalid) {
            'event' => {
              'event': 'accept',
              'payload': {'media': 'video', 'camera': 'off'},
            },
            'expired' => {
              'created_at_ms': _now
                  .subtract(const Duration(seconds: 40))
                  .millisecondsSinceEpoch,
              'expires_at_ms': _now.millisecondsSinceEpoch,
            },
            _ => {
              'created_at_ms': _now
                  .add(const Duration(seconds: 1))
                  .millisecondsSinceEpoch,
              'expires_at_ms': _now
                  .add(const Duration(seconds: 41))
                  .millisecondsSinceEpoch,
            },
          },
        ),
      );
      expect((await h.prepare())?.type, CallEventType.negotiationFailed);
      expect(h.registrations, 0);
      expect(h.store.read(_call), isNull);
      expect(h.v2.signals, isEmpty);
      expect(h.port.legacy, isEmpty);
    });
  }

  for (final boundary in ['endpoint', 'native']) {
    test(
      'v2 cancellation across $boundary await cannot revive preparation',
      () async {
        final h = _Harness();
        final reached = Completer<void>();
        final release = Completer<void>();
        Future<void> block() async {
          reached.complete();
          await release.future;
        }

        if (boundary == 'endpoint') {
          h.port.beforePrepare = block;
        } else {
          h.onRegister = (_) async {
            await block();
            return true;
          };
        }
        final preparing = h.prepare();
        await reached.future;
        h.current = false;
        release.complete();
        expect(await preparing, isNull);
        expect(h.store.read(_call), isNull);
        expect(h.v2.signals, isEmpty);
        expect(h.port.legacy, isEmpty);
        expect(h.registrations, boundary == 'native' ? 1 : 0);
      },
    );
  }

  for (final boundary in ['native', 'send']) {
    test(
      'v2 original invite expiry across $boundary cannot be extended',
      () async {
        final h = _Harness();
        if (boundary == 'native') {
          h.onRegister = (_) async {
            h.now = _now.add(const Duration(seconds: 41));
            return true;
          };
          expect((await h.prepare())?.type, CallEventType.negotiationFailed);
          expect(h.store.read(_call), isNull);
        } else {
          await h.prepareV2();
          h.now = _now.add(const Duration(seconds: 41));
          expect((await h.sendInvite())?.type, CallEventType.negotiationFailed);
        }
        expect(h.v2.signals, isEmpty);
        expect(h.port.legacy, isEmpty);
        expect(h.ids, 0);
      },
    );
  }

  for (final throwsError in [false, true]) {
    test(
      'v2 native refusal error=$throwsError purges only its own context',
      () async {
        final h = _Harness();
        h.store.storeOutgoingV2(
          invite: _invite(callId: _other),
          callHandle: _otherHandle,
        );
        h.onRegister = (_) async {
          if (throwsError) throw StateError('private native detail');
          return false;
        };
        expect((await h.prepare())?.type, CallEventType.negotiationFailed);
        expect(h.store.read(_call), isNull);
        expect(h.store.read(_other)?.preparedOutgoingV2Invite?.callId, _other);
        expect(h.v2.signals, isEmpty);
        expect(h.port.legacy, isEmpty);
      },
    );
  }

  test('v2 ringing uses the authenticated peers and shared metadata', () async {
    final h = _Harness()..incoming();
    expect(
      await h.executor.execute(
        const CallEffect(CallEffectType.sendRinging),
        _snapshot(CallState.ringing, incoming: true),
      ),
      isNull,
    );
    final ringing = h.v2.signals.single;
    expect(ringing.event, CallSignalV2Type.ringing);
    expect(ringing.payload, isEmpty);
    expect(ringing.senderAccountPeerId, 'local-account');
    expect(ringing.senderDevicePeerId, 'local-device');
    expect(ringing.recipientAccountPeerId, 'remote-account');
    expect(ringing.recipientDevicePeerId, 'remote-device');
    expect(ringing.senderSequence, 1);
    expect(ringing.iceGeneration, 2);
    expect(ringing.createdAtMs, _now.millisecondsSinceEpoch);
    expect(
      ringing.expiresAtMs,
      _now.add(const Duration(seconds: 40)).millisecondsSinceEpoch,
    );
    expect(h.store.read(_call)?.nextSenderSequence, 2);
    expect(h.port.legacy, isEmpty);
  });

  for (final media in CallMediaKind.values) {
    test('v2 accept uses explicit $media choice with camera off', () async {
      final h = _Harness()..incoming();
      h.store.recordLocalAcceptance(_call, media: media);
      expect(
        await h.executor.execute(
          const CallEffect(CallEffectType.sendAccept),
          _snapshot(CallState.accepted, incoming: true),
        ),
        isNull,
      );
      expect(h.v2.signals.single.event, CallSignalV2Type.accept);
      expect(h.v2.signals.single.payload, {
        'media': media.name,
        'camera': 'off',
      });
      expect(h.store.read(_call)?.initialAcceptedMedia, media);
      expect(h.port.legacy, isEmpty);
    });
  }

  test(
    'v2 accept never infers a local choice from the remote video invite',
    () async {
      final h = _Harness()..incoming();
      final result = await h.executor.execute(
        const CallEffect(CallEffectType.sendAccept),
        _snapshot(CallState.accepted, incoming: true),
      );
      expect(result?.type, CallEventType.negotiationFailed);
      expect(h.v2.signals, isEmpty);
      expect(h.port.legacy, isEmpty);
    },
  );

  for (final boundary in ['flag', 'port']) {
    test(
      'v2 incoming control refuses absent $boundary without downgrade',
      () async {
        final h = _Harness(
          enabled: boundary != 'flag',
          typedPort: boundary != 'port',
        )..incoming();
        final result = await h.executor.execute(
          const CallEffect(CallEffectType.sendRinging),
          _snapshot(CallState.ringing, incoming: true),
        );
        expect(result?.type, CallEventType.negotiationFailed);
        expect(h.port.legacy, isEmpty);
      },
    );
  }

  for (final effect in [
    CallEffectType.sendReject,
    CallEffectType.sendTerminate,
  ]) {
    test('v2 terminal $effect retains reason and purges its context', () async {
      final h = _Harness()..incoming();
      const reason = CallEndReason.declined;
      expect(
        await h.executor.execute(
          CallEffect(effect),
          _snapshot(CallState.ended, incoming: true, reason: reason),
        ),
        isNull,
      );
      expect(
        h.v2.signals.single.event,
        effect == CallEffectType.sendReject
            ? CallSignalV2Type.reject
            : CallSignalV2Type.terminate,
      );
      expect(h.v2.signals.single.payload, {'reason': reason.wireName});
      expect(h.store.read(_call), isNull);
      expect(h.port.legacy, isEmpty);
    });
  }

  for (final fail in [false, true]) {
    test(
      'v2 busy failure=$fail belongs only to the pending incoming call',
      () async {
        final h = _Harness();
        h.store.storeOutgoingV2(invite: _invite(), callHandle: _handle);
        h.incoming(callId: _other, handle: _otherHandle);
        h.v2.onSend = (_) async {
          if (fail) throw StateError('private transport detail');
          return _receipt();
        };
        expect(
          await h.executor.execute(
            const CallEffect(CallEffectType.sendBusy),
            _snapshot(CallState.connected),
          ),
          isNull,
        );
        final busy = h.v2.signals.single;
        expect(busy.callId, _other);
        expect(busy.event, CallSignalV2Type.reject);
        expect(busy.payload, {'reason': 'busy'});
        expect(h.v2.handles.single, _otherHandle);
        expect(h.store.read(_other), isNull);
        expect(h.store.read(_call)?.preparedOutgoingV2Invite, isNotNull);
        expect(h.port.legacy, isEmpty);
      },
    );
  }

  test(
    'v2 transport failure cannot fall back to a second legacy invite',
    () async {
      final h = _Harness();
      await h.prepareV2();
      h.v2.onSend = (_) async => throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.transportUnavailable,
      );
      expect((await h.sendInvite())?.type, CallEventType.negotiationFailed);
      expect(h.v2.signals.single, same(h.port.invite));
      expect(
        h.store.read(_call)?.callHandle,
        _handle,
        reason: 'terminal retirement still owns the failed invite context',
      );
      expect(h.port.legacy, isEmpty);
    },
  );

  test(
    'v2 terminal waits for stored invite custody and preserves the mailbox',
    () async {
      final h = _Harness();
      final settled = Completer<void>();
      h.v2.onSend = (signal) async => signal.event == CallSignalV2Type.invite
          ? _receipt(stored: true, wake: true, settled: settled.future)
          : _receipt();
      await h.prepareV2();
      expect((await h.sendInvite())?.type, CallEventType.wakeRequested);
      final ended = _snapshot(
        CallState.ended,
        reason: CallEndReason.callerCancelled,
      );
      final terminal = h.executor.execute(
        const CallEffect(CallEffectType.sendTerminate),
        ended,
      );
      final retired = h.executor.retireOutgoingPreconnectInvite(ended);
      await Future<void>.delayed(Duration.zero);
      expect(h.v2.signals.map((s) => s.event), [CallSignalV2Type.invite]);
      expect(h.cancelled, isEmpty);
      settled.complete();
      expect(await terminal, isNull);
      await retired;
      expect(h.v2.signals.map((s) => s.event), [
        CallSignalV2Type.invite,
        CallSignalV2Type.terminate,
      ]);
      expect(h.v2.signals.map((s) => s.senderSequence), [7, 8]);
      expect(h.v2.signals.last.payload, {'reason': 'caller_cancelled'});
      expect(h.v2.handles, [_handle, _handle]);
      expect(h.cancelled, isEmpty);
      expect(h.port.legacy, isEmpty);
      h.store.purge(_call);
      expect(h.store.read(_call), isNull);
    },
  );

  test(
    'v2 direct invite retirement waits for custody and coalesces cleanup',
    () async {
      final h = _Harness();
      final settled = Completer<void>();
      h.v2.onSend = (_) async => _receipt(settled: settled.future);
      await h.prepareV2();
      expect((await h.sendInvite())?.type, CallEventType.directAccepted);
      final ended = _snapshot(
        CallState.ended,
        reason: CallEndReason.callerCancelled,
      );
      final first = h.executor.retireOutgoingPreconnectInvite(ended);
      final second = h.executor.retireOutgoingPreconnectInvite(ended);
      await Future<void>.delayed(Duration.zero);
      expect(h.cancelled, isEmpty);
      settled.complete();
      await Future.wait([first, second]);
      expect(h.cancelled, [('remote-device', _handle)]);
      await h.executor.retireOutgoingPreconnectInvite(ended);
      expect(h.cancelled, hasLength(1));
      expect(h.port.legacy, isEmpty);
    },
  );

  test(
    'v2 controls share metadata with negotiation after the prepared invite',
    () async {
      final h = _Harness();
      await h.prepareV2();
      await h.sendInvite();
      expect(
        h.store.reserveNextMetadata(_call, iceGeneration: 3).senderSequence,
        8,
      );
      await h.executor.execute(
        const CallEffect(CallEffectType.sendTerminate),
        _snapshot(CallState.ended, reason: CallEndReason.localHangup),
      );
      expect(h.v2.signals.map((s) => s.senderSequence), [7, 9]);
      expect(h.v2.signals.last.iceGeneration, 3);
      expect(h.ids, 1);
      expect(h.port.legacy, isEmpty);
    },
  );

  test('v2 prepared invitation stays out of diagnostics', () async {
    final h = _Harness();
    await h.prepareV2();
    final preparation = OutgoingCallSignalingPreparation.v2(
      callHandle: _handle,
      invite: _invite(),
    );
    final diagnostic = '$preparation ${h.store.read(_call)} ${h.executor}';
    for (final secret in [
      _handle,
      _call.value,
      'local-device',
      'remote-account',
      'capabilities',
      jsonEncode(_invite().payload),
    ]) {
      expect(diagnostic, isNot(contains(secret)));
    }
  });
}
