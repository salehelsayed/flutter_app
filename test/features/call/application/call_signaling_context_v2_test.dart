import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/voice_call_feature_flags.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_test/flutter_test.dart';

final _call = CallId.parse('11111111-1111-4111-8111-111111111111');
const _handle = '22222222-2222-4222-8222-222222222222';
const _otherHandle = '33333333-3333-4333-8333-333333333333';
const _negotiation = '44444444-4444-4444-8444-444444444444';
const _switch = '55555555-5555-4555-8555-555555555555';

Map<String, Object?> _map({
  String event = 'invite',
  int sequence = 1,
  int generation = 0,
  String media = 'video',
  bool outgoing = false,
  Map<String, Object?>? payload,
}) => {
  'schema': CallSignalV2.schema,
  'call_id': _call.value,
  'message_id':
      'aaaaaaaa-aaaa-4aaa-8aaa-${sequence.toRadixString(16).padLeft(12, '0')}',
  'event': event,
  'sender_account_peer_id': outgoing ? 'local-account' : 'remote-account',
  'sender_device_peer_id': outgoing ? 'local-device' : 'remote-device',
  'recipient_account_peer_id': outgoing ? 'remote-account' : 'local-account',
  'recipient_device_peer_id': outgoing ? 'remote-device' : 'local-device',
  'sender_sequence': sequence,
  'ice_generation': generation,
  'created_at_ms': 1000,
  'expires_at_ms': 46000,
  'payload':
      payload ??
      switch (event) {
        'invite' => {
          'media': media,
          'camera': 'off',
          'capabilities': ['audio', 'video'],
        },
        'accept' => {'media': media, 'camera': 'off'},
        'offer' || 'answer' => {
          'negotiation_id': _negotiation,
          'purpose': 'initial',
          'switch_id': null,
          'media_revision': 0,
          'media': media,
          'description': 'private-sdp',
          'fingerprint': 'private-fingerprint',
        },
        'ice' => {
          'negotiation_id': _negotiation,
          'candidate': 'private-ice',
          'media_id': null,
          'media_line_index': null,
        },
        'media_commit' => {
          'switch_id': _switch,
          'media_revision': 1,
          'media': media,
        },
        'media_abort' => {
          'switch_id': _switch,
          'base_revision': 0,
          'media_revision': 1,
          'media': 'audio',
          'reason': 'timeout',
        },
        'terminate' || 'reject' => {'reason': 'unsupported'},
        _ => {},
      },
};

CallSignalV2 _v2({
  String event = 'invite',
  int sequence = 1,
  int generation = 0,
  String media = 'video',
  bool outgoing = false,
}) => CallSignalV2.fromMap(
  _map(
    event: event,
    sequence: sequence,
    generation: generation,
    media: media,
    outgoing: outgoing,
  ),
  videoEnabled: true,
);

CallSignal _v1({
  String event = 'terminate',
  String reason = 'unsupported',
  int sequence = 2,
  String senderDevice = 'remote-device',
  Map<String, Object?>? payload,
}) => CallSignal.fromMap({
  ..._map(event: event, sequence: sequence),
  'schema': CallSignal.schema,
  'sender_device_peer_id': senderDevice,
  'payload':
      payload ??
      (event == 'terminate' || event == 'reject' ? {'reason': reason} : {}),
});

Matcher _refused(CallSignalingContextErrorCode code) => throwsA(
  isA<CallSignalingContextException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

void _incoming(CallSignalingContextStore store, {String media = 'video'}) =>
    store.captureAuthenticatedV2(
      signal: _v2(media: media),
      callHandle: _handle,
    );

void _outgoing(CallSignalingContextStore store, {String media = 'video'}) =>
    store.storeOutgoingV2(
      invite: _v2(media: media, outgoing: true),
      callHandle: _handle,
    );

void main() {
  late CallSignalingContextStore store;
  setUp(() => store = CallSignalingContextStore(videoEnabled: true));

  test('video production and local flags are independently default off', () {
    expect(defaultVoiceCallFeatureFlags()['video_call_v2_enabled'], isFalse);
    expect(productionVoiceCallFeatureFlags()['video_call_v2_enabled'], isFalse);
    final changed = defaultVoiceCallFeatureFlags()
      ..['video_call_v2_enabled'] = true;
    expect(changed['video_call_v2_enabled'], isTrue);
    expect(defaultVoiceCallFeatureFlags()['video_call_v2_enabled'], isFalse);
  });

  test('default context store refuses v2 before creating a context', () {
    final disabled = CallSignalingContextStore();
    expect(
      () => _incoming(disabled),
      _refused(CallSignalingContextErrorCode.invalidContext),
    );
    expect(
      () => _outgoing(disabled),
      _refused(CallSignalingContextErrorCode.invalidContext),
    );
    expect(disabled.length, 0);
  });

  test('typed outgoing invite pins v2 media, identities and next sequence', () {
    final invite = _v2(outgoing: true);
    store.storeOutgoingV2(invite: invite, callHandle: _handle);
    final context = store.read(_call)!;
    expect(context.wireVersion, CallWireVersion.v2);
    expect(context.direction, CallDirection.outgoing);
    expect(context.requestedMedia, CallMediaKind.video);
    expect(context.initialAcceptedMedia, isNull);
    expect(context.localDevicePeerId, invite.senderDevicePeerId);
    expect(context.remoteDevicePeerId, invite.recipientDevicePeerId);
    expect(context.invitePayload, invite.payload);
    expect(
      store.reserveNextMetadata(_call, iceGeneration: 0).senderSequence,
      2,
    );
    store.storeOutgoingV2(invite: invite, callHandle: _handle);
    expect(store.read(_call)!.nextSenderSequence, 3);
  });

  test(
    'outgoing v2 requires an actual invite and cannot retarget the call',
    () {
      expect(
        () => store.storeOutgoingV2(
          invite: _v2(event: 'accept', outgoing: true),
          callHandle: _handle,
        ),
        _refused(CallSignalingContextErrorCode.invalidContext),
      );
      expect(store.length, 0);
      _outgoing(store);
      expect(
        () => _outgoing(store, media: 'audio'),
        _refused(CallSignalingContextErrorCode.bindingConflict),
      );
      expect(store.read(_call)!.requestedMedia, CallMediaKind.video);
    },
  );

  test('incoming v2 retains the immutable authenticated invite metadata', () {
    _incoming(store);
    final context = store.takePendingIncomingInvite()!;
    expect(context.wireVersion, CallWireVersion.v2);
    expect(context.direction, CallDirection.incoming);
    expect(context.requestedMedia, CallMediaKind.video);
    expect(context.invitePayload, _v2().payload);
    expect(
      () => context.invitePayload['media'] = 'audio',
      throwsUnsupportedError,
    );
    expect(
      () => (context.invitePayload['capabilities'] as List)[0] = 'changed',
      throwsUnsupportedError,
    );
    expect(store.takePendingIncomingInvite(), isNull);
  });

  test('incoming v1 also retains its already-authenticated invite payload', () {
    final signal = _v1(
      event: 'invite',
      sequence: 1,
      payload: {
        'capabilities': ['audio'],
        'metadata': {'origin': 'fixture'},
      },
    );
    store.captureAuthenticated(signal: signal, callHandle: _handle);
    final context = store.read(_call)!;
    expect(context.wireVersion, CallWireVersion.v1);
    expect(context.requestedMedia, CallMediaKind.audio);
    expect(context.invitePayload, signal.payload);
    expect(
      () => (context.invitePayload['metadata'] as Map)['origin'] = 'changed',
      throwsUnsupportedError,
    );
  });

  test('incoming initial requested media cannot change on another invite', () {
    _incoming(store);
    expect(
      () => store.captureAuthenticatedV2(
        signal: _v2(media: 'audio', sequence: 2),
        callHandle: _handle,
      ),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    expect(store.read(_call)!.remoteSenderSequence, 1);
    expect(store.read(_call)!.requestedMedia, CallMediaKind.video);
  });

  for (final media in CallMediaKind.values) {
    test(
      'video invitation accepts explicit initial ${media.name} without changing request',
      () {
        _outgoing(store);
        store.captureAuthenticatedV2(
          signal: _v2(event: 'accept', media: media.name),
          callHandle: _handle,
        );
        expect(store.read(_call)!.requestedMedia, CallMediaKind.video);
        expect(store.read(_call)!.initialAcceptedMedia, media);
      },
    );
  }

  test('initial audio invite cannot accept video', () {
    _outgoing(store, media: 'audio');
    expect(
      () => store.captureAuthenticatedV2(
        signal: _v2(event: 'accept'),
        callHandle: _handle,
      ),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    expect(store.read(_call)!.initialAcceptedMedia, isNull);
    expect(store.read(_call)!.remoteSenderSequence, 0);
  });

  test('authenticated initial acceptance is immutable and duplicate-safe', () {
    _outgoing(store);
    final accepted = _v2(event: 'accept', media: 'audio');
    store.captureAuthenticatedV2(signal: accepted, callHandle: _handle);
    store.captureAuthenticatedV2(signal: accepted, callHandle: _handle);
    expect(
      () => store.captureAuthenticatedV2(
        signal: _v2(event: 'accept', sequence: 2),
        callHandle: _handle,
      ),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    expect(store.read(_call)!.initialAcceptedMedia, CallMediaKind.audio);
    expect(store.read(_call)!.remoteSenderSequence, 1);
  });

  test(
    'local initial answer produces a new snapshot and remains immutable',
    () {
      _incoming(store);
      final before = store.read(_call)!;
      store.recordLocalAcceptance(_call, media: CallMediaKind.audio);
      store.recordLocalAcceptance(_call, media: CallMediaKind.audio);
      expect(before.initialAcceptedMedia, isNull);
      expect(store.read(_call)!.initialAcceptedMedia, CallMediaKind.audio);
      expect(
        () => store.recordLocalAcceptance(_call, media: CallMediaKind.video),
        _refused(CallSignalingContextErrorCode.bindingConflict),
      );
    },
  );

  test(
    'local answer cannot manufacture a remote acceptance on an outgoing call',
    () {
      _outgoing(store);
      expect(
        () => store.recordLocalAcceptance(_call, media: CallMediaKind.video),
        _refused(CallSignalingContextErrorCode.bindingConflict),
      );
      expect(store.read(_call)!.initialAcceptedMedia, isNull);
    },
  );

  test('remote caller cannot answer its own incoming invitation', () {
    _incoming(store);
    expect(
      () => store.captureAuthenticatedV2(
        signal: _v2(event: 'accept', sequence: 2),
        callHandle: _handle,
      ),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    expect(store.read(_call)!.initialAcceptedMedia, isNull);
  });

  test('initial offer requires local acceptance and the accepted media', () {
    _incoming(store);
    expect(
      () => store.captureAuthenticatedV2(
        signal: _v2(event: 'offer', sequence: 2),
        callHandle: _handle,
      ),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    store.recordLocalAcceptance(_call, media: CallMediaKind.audio);
    expect(
      () => store.captureAuthenticatedV2(
        signal: _v2(event: 'offer', sequence: 2),
        callHandle: _handle,
      ),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    expect(store.read(_call)!.initialOfferReceived, isFalse);
    store.captureAuthenticatedV2(
      signal: _v2(event: 'offer', sequence: 2, media: 'audio'),
      callHandle: _handle,
    );
    expect(store.read(_call)!.initialOfferReceived, isTrue);
    expect(store.read(_call)!.initialAcceptedMedia, CallMediaKind.audio);
  });

  test('initial answer cannot precede authenticated remote acceptance', () {
    _outgoing(store);
    expect(
      () => store.captureAuthenticatedV2(
        signal: _v2(event: 'answer'),
        callHandle: _handle,
      ),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    expect(store.read(_call)!.remoteSenderSequence, 0);
  });

  for (final accepted in [false, true]) {
    test(
      'same-bound v1 cleanup is admitted before offer with local accept=$accepted',
      () {
        _incoming(store);
        if (accepted) {
          store.recordLocalAcceptance(_call, media: CallMediaKind.video);
        }
        store.captureAuthenticated(signal: _v1(), callHandle: _handle);
        final context = store.read(_call)!;
        expect(context.wireVersion, CallWireVersion.v2);
        expect(context.requestedMedia, CallMediaKind.video);
        expect(
          context.initialAcceptedMedia,
          accepted ? CallMediaKind.video : null,
        );
        expect(context.initialOfferReceived, isFalse);
        expect(context.remoteSenderSequence, 2);
      },
    );
  }

  test('v1 cleanup is no longer admitted after the initial offer arrives', () {
    _incoming(store);
    store.recordLocalAcceptance(_call, media: CallMediaKind.video);
    store.captureAuthenticatedV2(
      signal: _v2(event: 'offer', sequence: 2),
      callHandle: _handle,
    );
    expect(
      () => store.captureAuthenticated(
        signal: _v1(sequence: 3),
        callHandle: _handle,
      ),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    expect(store.read(_call)!.remoteSenderSequence, 2);
  });

  test(
    'the outgoing caller cannot use the incoming-only v1 cleanup exception',
    () {
      _outgoing(store);
      expect(
        () => store.captureAuthenticated(signal: _v1(), callHandle: _handle),
        _refused(CallSignalingContextErrorCode.bindingConflict),
      );
    },
  );

  for (final key in [
    'sender_account_peer_id',
    'sender_device_peer_id',
    'recipient_account_peer_id',
    'recipient_device_peer_id',
  ]) {
    test('legacy cleanup retains the exact $key binding', () {
      _incoming(store);
      final wrong = CallSignal.fromMap({
        ..._v1().toMap(),
        key: 'other-authority',
      });
      expect(
        () => store.captureAuthenticated(signal: wrong, callHandle: _handle),
        _refused(CallSignalingContextErrorCode.bindingConflict),
      );
      expect(store.read(_call)!.remoteSenderSequence, 1);
    });
  }

  test('legacy cleanup retains the exact routing handle', () {
    _incoming(store);
    expect(
      () => store.captureAuthenticated(signal: _v1(), callHandle: _otherHandle),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    expect(store.read(_call)!.callHandle, _handle);
  });

  for (final event in ['invite', 'accept', 'reject', 'terminate']) {
    test('other v1 $event cannot change a v2 context', () {
      _incoming(store);
      final signal = _v1(event: event, reason: 'caller_cancelled');
      expect(
        () => store.captureAuthenticated(signal: signal, callHandle: _handle),
        _refused(CallSignalingContextErrorCode.bindingConflict),
      );
      expect(store.read(_call)!.remoteSenderSequence, 1);
    });
  }

  test('an existing v1 context cannot be upgraded by a v2 message', () {
    store.captureAuthenticated(
      signal: _v1(event: 'invite', sequence: 1),
      callHandle: _handle,
    );
    expect(
      () => store.captureAuthenticatedV2(
        signal: _v2(event: 'accept', sequence: 2),
        callHandle: _handle,
      ),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    expect(store.read(_call)!.wireVersion, CallWireVersion.v1);
  });

  test('an outgoing binding cannot silently change back to v1', () {
    _outgoing(store);
    expect(
      () => store.storeOutgoing(
        callId: _call,
        callHandle: _handle,
        localAccountPeerId: 'local-account',
        localDevicePeerId: 'local-device',
        remoteAccountPeerId: 'remote-account',
        remoteDevicePeerId: 'remote-device',
      ),
      _refused(CallSignalingContextErrorCode.bindingConflict),
    );
    expect(store.read(_call)!.wireVersion, CallWireVersion.v2);
  });

  test('v2 media reordering preserves the authenticated high-water mark', () {
    _incoming(store);
    store.recordLocalAcceptance(_call, media: CallMediaKind.video);
    store.captureAuthenticatedV2(
      signal: _v2(event: 'media_commit', sequence: 67),
      callHandle: _handle,
    );
    store.captureAuthenticatedV2(
      signal: _v2(event: 'media_abort', sequence: 3),
      callHandle: _handle,
    );
    expect(store.read(_call)!.remoteSenderSequence, 67);
    expect(store.read(_call)!.initialAcceptedMedia, CallMediaKind.video);
    expect(
      () => store.captureAuthenticatedV2(
        signal: _v2(event: 'media_abort', sequence: 2),
        callHandle: _handle,
      ),
      _refused(CallSignalingContextErrorCode.nonMonotonicMetadata),
    );
  });

  test(
    'v2 reordering cannot cross ICE generations but a terminal retains authority',
    () {
      _incoming(store);
      store.recordLocalAcceptance(_call, media: CallMediaKind.video);
      store.captureAuthenticatedV2(
        signal: _v2(event: 'ice', sequence: 4, generation: 1),
        callHandle: _handle,
      );
      expect(
        () => store.captureAuthenticatedV2(
          signal: _v2(event: 'ice', sequence: 3),
          callHandle: _handle,
        ),
        _refused(CallSignalingContextErrorCode.nonMonotonicMetadata),
      );
      store.captureAuthenticatedV2(
        signal: _v2(event: 'terminate', sequence: 5),
        callHandle: _handle,
      );
      expect(store.read(_call)!.iceGeneration, 1);
      expect(store.read(_call)!.remoteSenderSequence, 5);
    },
  );

  test(
    'an unknown v2 offer cannot construct an invited or accepted context',
    () {
      expect(
        () => store.captureAuthenticatedV2(
          signal: _v2(event: 'offer'),
          callHandle: _handle,
        ),
        _refused(CallSignalingContextErrorCode.contextUnavailable),
      );
      expect(store.length, 0);
      expect(store.takePendingIncomingInvite(), isNull);
    },
  );

  test(
    'terminal-before-invite retains routing metadata without queueing presentation',
    () {
      store.captureAuthenticatedV2(
        signal: _v2(event: 'terminate'),
        callHandle: _handle,
      );
      expect(store.read(_call)!.wireVersion, CallWireVersion.v2);
      expect(store.read(_call)!.initialAcceptedMedia, isNull);
      expect(store.takePendingIncomingInvite(), isNull);
      // Whole-call terminal tombstones still belong to the canonical coordinator.
    },
  );

  test('v2 shares the existing bounded context capacity and purge', () {
    final bounded = CallSignalingContextStore(
      maxContexts: 1,
      videoEnabled: true,
    );
    _incoming(bounded);
    final other = CallSignalV2.fromMap({
      ..._map(outgoing: true),
      'call_id': '99999999-9999-4999-8999-999999999999',
    }, videoEnabled: true);
    expect(
      () => bounded.storeOutgoingV2(invite: other, callHandle: _otherHandle),
      _refused(CallSignalingContextErrorCode.capacityExceeded),
    );
    bounded.purge(_call);
    expect(bounded.takePendingIncomingInvite(), isNull);
    expect(bounded.read(_call), isNull);
    bounded.storeOutgoingV2(invite: other, callHandle: _otherHandle);
    expect(bounded.length, 1);
  });

  test('media and peer material remain absent from context diagnostics', () {
    _incoming(store);
    store.recordLocalAcceptance(_call, media: CallMediaKind.video);
    final diagnostic = '${store.read(_call)} $store';
    for (final secret in [
      _call.value,
      _handle,
      'remote-device',
      'video',
      'capabilities',
    ]) {
      expect(diagnostic, isNot(contains(secret)));
    }
  });
}
