import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final callId = CallId.parse('22222222-2222-4222-8222-222222222222');
  const createdAtMs = 1788091200000;
  const expiresAtMs = createdAtMs + 45000;

  Map<String, Object?> base(CallSignalType event) => <String, Object?>{
    'schema': 'mknoon.call_signal.v1',
    'call_id': callId.value,
    'message_id': '33333333-3333-4333-8333-333333333333',
    'event': event.wireName,
    'sender_account_peer_id': 'sender-account',
    'sender_device_peer_id': 'sender-device-peer',
    'recipient_account_peer_id': 'recipient-account',
    'recipient_device_peer_id': 'recipient-device-peer',
    'sender_sequence': 1,
    'ice_generation': 0,
    'created_at_ms': createdAtMs,
    'expires_at_ms': expiresAtMs,
    'payload': <String, Object?>{},
  };

  test('call id accepts only canonical random UUID-v4 grammar', () {
    expect(callId.value, '22222222-2222-4222-8222-222222222222');
    for (final invalid in <String>[
      '',
      '22222222222242228222222222222222',
      '22222222-2222-3222-8222-222222222222',
      '22222222-2222-4222-7222-222222222222',
      'ZZZZ2222-2222-4222-8222-222222222222',
    ]) {
      expect(() => CallId.parse(invalid), throwsFormatException);
    }
  });

  test(
    'invite permits bounded metadata but recursively forbids media data',
    () {
      final map = base(CallSignalType.invite);
      map['payload'] = <String, Object?>{
        'capabilities': <String>['voice_call_v1'],
        'metadata': <String, Object?>{'audio': true},
      };
      final signal = CallSignal.fromMap(map);
      expect(signal.event, CallSignalType.invite);

      for (final forbidden in <String>[
        'sdp',
        'candidate',
        'candidates',
        'offer',
        'answer',
      ]) {
        final invalid = base(CallSignalType.invite);
        invalid['payload'] = <String, Object?>{
          'metadata': <String, Object?>{
            'nested': <String, Object?>{forbidden: 'opaque-secret'},
          },
        };
        expect(() => CallSignal.fromMap(invalid), throwsFormatException);
      }
    },
  );

  test(
    'validated nested payload cannot be mutated through input or output',
    () {
      final metadata = <String, Object?>{'audio': true};
      final map = base(CallSignalType.invite);
      map['payload'] = <String, Object?>{'metadata': metadata};

      final signal = CallSignal.fromMap(map);
      metadata['sdp'] = 'late-injected-secret';
      expect(
        signal.payload.toString(),
        isNot(contains('late-injected-secret')),
      );

      final serialized = signal.toMap();
      final serializedPayload = serialized['payload']! as Map<String, Object?>;
      final serializedMetadata =
          serializedPayload['metadata']! as Map<Object?, Object?>;
      serializedMetadata['candidate'] = 'late-output-secret';
      expect(signal.toMap().toString(), isNot(contains('late-output-secret')));
    },
  );

  test('offer and answer require an authenticated fingerprint', () {
    for (final event in <CallSignalType>[
      CallSignalType.offer,
      CallSignalType.answer,
    ]) {
      final map = base(event);
      map['payload'] = <String, Object?>{
        'description': 'opaque-description',
        'fingerprint': 'sha-256 AA:BB:CC',
      };
      final signal = CallSignal.fromMap(map);
      expect(signal.payload['fingerprint'], isNotEmpty);

      (map['payload'] as Map<String, Object?>).remove('fingerprint');
      expect(() => CallSignal.fromMap(map), throwsFormatException);
    }
  });

  test(
    'schema rejects unknown fields sequence zero and bad ice generation',
    () {
      final unknown = base(CallSignalType.ringing)..['unexpected'] = true;
      expect(() => CallSignal.fromMap(unknown), throwsFormatException);

      final zeroSequence = base(CallSignalType.ringing)
        ..['sender_sequence'] = 0;
      expect(() => CallSignal.fromMap(zeroSequence), throwsFormatException);

      final badGeneration = base(CallSignalType.ringing)
        ..['ice_generation'] = -1;
      expect(() => CallSignal.fromMap(badGeneration), throwsFormatException);
    },
  );

  test('preconnect events have a hard 45 second lifetime', () {
    for (final event in <CallSignalType>[
      CallSignalType.invite,
      CallSignalType.ringing,
      CallSignalType.accept,
      CallSignalType.reject,
    ]) {
      final map = base(event)..['expires_at_ms'] = createdAtMs + 45001;
      expect(() => CallSignal.fromMap(map), throwsFormatException);
    }
  });

  test('the complete canonical signal is bounded to 96 KiB', () {
    final oversized = base(CallSignalType.offer);
    oversized['payload'] = <String, Object?>{
      'description': 'd' * CallSignal.maximumEncodedBytes,
      'fingerprint': 'sha-256 AA:BB:CC',
    };

    expect(() => CallSignal.fromMap(oversized), throwsFormatException);
  });

  test('invite metadata rejects non-finite JSON numbers', () {
    final invalid = base(CallSignalType.invite);
    invalid['payload'] = <String, Object?>{
      'metadata': <String, Object?>{'gain': double.nan},
    };

    expect(() => CallSignal.fromMap(invalid), throwsFormatException);
  });

  test('diagnostics and toString omit identities and signaling payload', () {
    final map = base(CallSignalType.offer);
    map['payload'] = <String, Object?>{
      'description': 'opaque-description-secret',
      'fingerprint': 'sha-256 AA:BB:CC',
    };
    final signal = CallSignal.fromMap(map);
    final diagnostics = '${signal.toDiagnosticMap()} $signal';

    expect(diagnostics, isNot(contains('sender-account')));
    expect(diagnostics, isNot(contains('recipient-account')));
    expect(diagnostics, isNot(contains('opaque-description-secret')));
    expect(diagnostics, isNot(contains(callId.value)));
  });
}
