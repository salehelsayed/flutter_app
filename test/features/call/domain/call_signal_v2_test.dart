import 'dart:convert';

import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_test/flutter_test.dart';

const _callId = '22222222-2222-4222-8222-222222222222';
const _messageId = '33333333-3333-4333-8333-333333333333';
const _negotiationId = '44444444-4444-4444-8444-444444444444';
const _switchId = '55555555-5555-4555-8555-555555555555';
const _created = 1788091200000;

Map<String, Object?> _payload(CallSignalV2Type event) => switch (event) {
  CallSignalV2Type.invite => {
    'media': 'video',
    'camera': 'off',
    'capabilities': <String>['audio', 'video'],
  },
  CallSignalV2Type.ringing => {},
  CallSignalV2Type.accept => {'media': 'audio', 'camera': 'off'},
  CallSignalV2Type.reject ||
  CallSignalV2Type.terminate => {'reason': 'unsupported'},
  CallSignalV2Type.offer || CallSignalV2Type.answer => {
    'negotiation_id': _negotiationId,
    'purpose': 'initial',
    'switch_id': null,
    'media_revision': 0,
    'media': 'audio',
    'description': 'private-sdp-fixture',
    'fingerprint': 'private-fingerprint-fixture',
  },
  CallSignalV2Type.ice => {
    'negotiation_id': _negotiationId,
    'candidate': 'private-candidate-fixture',
    'media_id': null,
    'media_line_index': null,
  },
  CallSignalV2Type.iceRestart => {
    'negotiation_id': _negotiationId,
    'media_revision': 0,
  },
  CallSignalV2Type.mediaRequest => {
    'switch_id': _switchId,
    'base_revision': 0,
    'target_media': 'video',
    'camera': 'off',
  },
  CallSignalV2Type.mediaResponse => {
    'switch_id': _switchId,
    'base_revision': 0,
    'decision': 'accept',
    'camera': 'off',
  },
  CallSignalV2Type.mediaCommit || CallSignalV2Type.mediaCommitAck => {
    'switch_id': _switchId,
    'media_revision': 1,
    'media': 'video',
  },
  CallSignalV2Type.mediaAbort => {
    'switch_id': _switchId,
    'base_revision': 0,
    'media_revision': 0,
    'media': 'audio',
    'reason': 'timeout',
  },
  CallSignalV2Type.cameraState => {'media_revision': 0, 'state': 'paused'},
};

Map<String, Object?> _message(CallSignalV2Type event) => {
  'schema': 'mknoon.call_signal.v2',
  'call_id': _callId,
  'message_id': _messageId,
  'event': event.wireName,
  'sender_account_peer_id': 'private-sender-account',
  'sender_device_peer_id': 'private-sender-device',
  'recipient_account_peer_id': 'private-recipient-account',
  'recipient_device_peer_id': 'private-recipient-device',
  'sender_sequence': 1,
  'ice_generation': 0,
  'created_at_ms': _created,
  'expires_at_ms': _created + 45000,
  'payload': _payload(event),
};

void main() {
  group('BL16-U1 strict encrypted v2', () {
    test('valid v2 is rejected with the gate off by default', () {
      final input = _message(CallSignalV2Type.invite);
      expect(() => CallSignalV2.fromMap(input), throwsFormatException);
      expect(
        () => CallSignalV2.fromMap(input, videoEnabled: false),
        throwsFormatException,
      );
    });

    for (final event in CallSignalV2Type.values) {
      test('${event.wireName} exact canonical payload round-trips', () {
        final input = _message(event);
        final signal = CallSignalV2.fromMap(input, videoEnabled: true);
        expect(signal.event, event);
        expect(signal.toMap(), input);
        expect(jsonEncode(signal.toMap()), jsonEncode(input));
      });

      test('${event.wireName} rejects missing or extra payload keys', () {
        final input = _message(event);
        final original = _payload(event);
        for (final key in original.keys) {
          input['payload'] = Map<String, Object?>.of(original)..remove(key);
          expect(
            () => CallSignalV2.fromMap(input, videoEnabled: true),
            throwsFormatException,
            reason: 'missing $key',
          );
        }
        input['payload'] = {...original, 'unrecognized': true};
        expect(
          () => CallSignalV2.fromMap(input, videoEnabled: true),
          throwsFormatException,
        );
      });
    }

    test('does not relax the existing v1 parser', () {
      for (final event in CallSignalV2Type.values) {
        expect(
          () => CallSignal.fromMap(_message(event)),
          throwsFormatException,
        );
      }
      final accept = _message(CallSignalV2Type.accept)
        ..['schema'] = CallSignal.schema;
      expect(() => CallSignal.fromMap(accept), throwsFormatException);
    });

    test('requires the exact v2 top-level shape and closed event', () {
      final valid = _message(CallSignalV2Type.invite);
      for (final key in valid.keys) {
        final invalid = Map<String, Object?>.of(valid)..remove(key);
        expect(
          () => CallSignalV2.fromMap(invalid, videoEnabled: true),
          throwsFormatException,
        );
      }
      for (final changed in <Map<String, Object?>>[
        {...valid, 'schema': CallSignal.schema},
        {...valid, 'schema': 'mknoon.call_signal.v3'},
        {...valid, 'event': 'video_magic'},
        {...valid, 'media': 'video'},
        {...valid, 'payload': <Object?>[]},
      ]) {
        expect(
          () => CallSignalV2.fromMap(changed, videoEnabled: true),
          throwsFormatException,
        );
      }
    });

    test(
      'preserves UUID identity sequence generation and timestamp bounds',
      () {
        final input = _message(CallSignalV2Type.ringing);
        for (final mutation in <MapEntry<String, Object?>>[
          const MapEntry('call_id', 'not-a-uuid'),
          const MapEntry('message_id', '33333333-3333-3333-8333-333333333333'),
          const MapEntry('sender_account_peer_id', ''),
          const MapEntry('sender_device_peer_id', ' trailing '),
          MapEntry('recipient_account_peer_id', 'a' * 513),
          const MapEntry('recipient_device_peer_id', null),
          const MapEntry('sender_sequence', 0),
          const MapEntry('sender_sequence', 1.5),
          const MapEntry('ice_generation', -1),
          const MapEntry('created_at_ms', -1),
          const MapEntry('expires_at_ms', _created),
        ]) {
          expect(
            () => CallSignalV2.fromMap({
              ...input,
              mutation.key: mutation.value,
            }, videoEnabled: true),
            throwsFormatException,
            reason: mutation.key,
          );
        }
      },
    );

    test('preconnect retains the 45-second bound', () {
      for (final event in [
        CallSignalV2Type.invite,
        CallSignalV2Type.ringing,
        CallSignalV2Type.accept,
        CallSignalV2Type.reject,
      ]) {
        final input = _message(event)..['expires_at_ms'] = _created + 45001;
        expect(
          () => CallSignalV2.fromMap(input, videoEnabled: true),
          throwsFormatException,
        );
      }
    });

    test('signal byte bound includes multibyte SDP and the envelope', () {
      final input = _message(CallSignalV2Type.offer);
      input['payload'] = {
        ..._payload(CallSignalV2Type.offer),
        'description': 'é' * 60000,
      };
      expect(
        () => CallSignalV2.fromMap(input, videoEnabled: true),
        throwsFormatException,
      );
    });

    test('invite requires both ordered capabilities and coherent camera', () {
      for (final payload in <Map<String, Object?>>[
        {
          'media': 'audio',
          'camera': 'on',
          'capabilities': ['audio', 'video'],
        },
        {
          'media': 'screen',
          'camera': 'off',
          'capabilities': ['audio', 'video'],
        },
        {
          'media': 'video',
          'camera': 'paused',
          'capabilities': ['audio', 'video'],
        },
        {
          'media': 'video',
          'camera': 'off',
          'capabilities': ['video', 'audio'],
        },
        {
          'media': 'video',
          'camera': 'off',
          'capabilities': ['audio'],
        },
        {..._payload(CallSignalV2Type.invite), 'sdp': 'private'},
      ]) {
        expect(
          () => CallSignalV2.fromMap(
            _message(CallSignalV2Type.invite)..['payload'] = payload,
            videoEnabled: true,
          ),
          throwsFormatException,
        );
      }
    });

    test('audio invite and camera-off video answer remain valid', () {
      for (final event in [CallSignalV2Type.invite, CallSignalV2Type.accept]) {
        for (final media in ['audio', 'video']) {
          final input = _message(event);
          input['payload'] = {
            ..._payload(event),
            'media': media,
            'camera': 'off',
          };
          expect(
            CallSignalV2.fromMap(input, videoEnabled: true).toMap(),
            input,
          );
        }
      }
    });

    test('audio accept and audio switch request cannot enable a camera', () {
      for (final event in [
        CallSignalV2Type.accept,
        CallSignalV2Type.mediaRequest,
      ]) {
        final mediaKey = event == CallSignalV2Type.accept
            ? 'media'
            : 'target_media';
        final input = _message(event)
          ..['payload'] = {
            ..._payload(event),
            mediaKey: 'audio',
            'camera': 'on',
          };
        expect(
          () => CallSignalV2.fromMap(input, videoEnabled: true),
          throwsFormatException,
        );
      }
    });

    test('non-accept response cannot claim an enabled camera', () {
      for (final decision in [
        'decline',
        'busy',
        'stale',
        'superseded',
        'unsupported',
      ]) {
        final input = _message(CallSignalV2Type.mediaResponse);
        input['payload'] = {
          ..._payload(CallSignalV2Type.mediaResponse),
          'decision': decision,
          'camera': 'on',
        };
        expect(
          () => CallSignalV2.fromMap(input, videoEnabled: true),
          throwsFormatException,
        );
        (input['payload']! as Map<String, Object?>)['camera'] = 'off';
        expect(CallSignalV2.fromMap(input, videoEnabled: true).toMap(), input);
      }
    });

    test('SDP purpose binds initial and switching negotiation identities', () {
      for (final event in [CallSignalV2Type.offer, CallSignalV2Type.answer]) {
        for (final purpose in [
          'initial',
          'media_switch',
          'ice_restart',
          'media_repair',
        ]) {
          final input = _message(event);
          final needsSwitch =
              purpose == 'media_switch' || purpose == 'media_repair';
          input['payload'] = {
            ..._payload(event),
            'purpose': purpose,
            'switch_id': needsSwitch ? _switchId : null,
            'media_revision': purpose == 'media_switch' ? 1 : 0,
          };
          expect(
            CallSignalV2.fromMap(input, videoEnabled: true).toMap(),
            input,
          );
          (input['payload']! as Map<String, Object?>)['switch_id'] = needsSwitch
              ? null
              : _switchId;
          expect(
            () => CallSignalV2.fromMap(input, videoEnabled: true),
            throwsFormatException,
          );
        }
      }
    });

    test(
      'rejects malformed transaction identifiers revisions and closed enums',
      () {
        final mutations = <(CallSignalV2Type, String, Object?)>[
          (CallSignalV2Type.offer, 'negotiation_id', 'bad-id'),
          (CallSignalV2Type.offer, 'purpose', 'automatic_upgrade'),
          (CallSignalV2Type.offer, 'media_revision', 1),
          (CallSignalV2Type.offer, 'description', ''),
          (CallSignalV2Type.offer, 'fingerprint', ''),
          (CallSignalV2Type.ice, 'negotiation_id', null),
          (CallSignalV2Type.ice, 'candidate', ''),
          (CallSignalV2Type.ice, 'media_id', 1),
          (CallSignalV2Type.ice, 'media_line_index', 'zero'),
          (CallSignalV2Type.iceRestart, 'media_revision', -1),
          (CallSignalV2Type.mediaRequest, 'switch_id', 'bad-id'),
          (CallSignalV2Type.mediaRequest, 'base_revision', -1),
          (CallSignalV2Type.mediaRequest, 'target_media', 'screen'),
          (CallSignalV2Type.mediaResponse, 'decision', 'automatic'),
          (CallSignalV2Type.mediaCommit, 'media_revision', 1.5),
          (CallSignalV2Type.mediaCommitAck, 'media', 'screen'),
          (CallSignalV2Type.mediaAbort, 'media', 'video'),
          (CallSignalV2Type.mediaAbort, 'reason', 'free text'),
          (CallSignalV2Type.cameraState, 'state', 'muted'),
          (CallSignalV2Type.reject, 'reason', 'remote_permission_denied'),
          (CallSignalV2Type.terminate, 'reason', 'private reason'),
        ];
        for (final (event, key, value) in mutations) {
          final input = _message(event)
            ..['payload'] = {..._payload(event), key: value};
          expect(
            () => CallSignalV2.fromMap(input, videoEnabled: true),
            throwsFormatException,
            reason: '${event.wireName} $key',
          );
        }
      },
    );

    test('validated input and output cannot mutate retained payload', () {
      final input = _message(CallSignalV2Type.invite);
      final original = input['payload']! as Map<String, Object?>;
      final caps = original['capabilities']! as List<String>;
      final signal = CallSignalV2.fromMap(input, videoEnabled: true);
      caps.add('screen');
      original['camera'] = 'on';
      expect(signal.payload['camera'], 'off');
      expect(signal.payload['capabilities'], ['audio', 'video']);
      expect(() => signal.payload['camera'] = 'on', throwsUnsupportedError);
      expect(
        () => (signal.payload['capabilities']! as List).add('screen'),
        throwsUnsupportedError,
      );
      final output = signal.toMap()['payload']! as Map<String, Object?>;
      (output['capabilities']! as List).clear();
      output['camera'] = 'on';
      expect(signal.payload['camera'], 'off');
      expect(signal.payload['capabilities'], ['audio', 'video']);
    });

    test(
      'diagnostics omit identities media SDP candidates and fingerprints',
      () {
        for (final event in [
          CallSignalV2Type.invite,
          CallSignalV2Type.offer,
          CallSignalV2Type.ice,
        ]) {
          final signal = CallSignalV2.fromMap(
            _message(event),
            videoEnabled: true,
          );
          final diagnostic = '${signal.toDiagnosticMap()} $signal';
          for (final secret in [
            'private-',
            _callId,
            _messageId,
            _negotiationId,
            'video',
            'camera',
            'fingerprint',
          ]) {
            expect(diagnostic, isNot(contains(secret)));
          }
        }
      },
    );
  });
}
