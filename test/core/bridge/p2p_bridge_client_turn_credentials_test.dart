import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

class _TurnCredentialBridge extends Bridge {
  Map<String, dynamic>? request;
  String? rawResponse;
  Object? error;
  Map<String, dynamic> response = <String, dynamic>{'ok': true};

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    request = jsonDecode(message) as Map<String, dynamic>;
    if (error case final failure?) throw failure;
    return rawResponse ?? jsonEncode(response);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'failure flow preserves fixed native cause before rejected projection',
    () async {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));
      for (final code in ['NOT_INITIALIZED', 'TURN_CREDENTIALS_REJECTED']) {
        final result = await callP2PTurnCredentialsV1(
          _TurnCredentialBridge()
            ..response = {
              'ok': false,
              'errorCode': code,
              'failureDiagnostic': {
                'stage': 'connect',
                'kind': 'dial_aggregate',
                'dialCauseKind': 'all_dials_failed',
                'dialTransportKinds': ['network_unreachable', 'dial_backoff'],
                'dialComplete': true,
                'dialAllTransient': false,
                'dialAttemptCount': 2,
              },
            },
        );
        expect(result['errorCode'], 'TURN_CREDENTIALS_REJECTED');
        final details = events.last['details'] as Map;
        expect(details['nativeErrorCode'], code);
        expect(details['nativeFailureStage'], 'connect');
        expect(details['nativeFailureKind'], 'dial_aggregate');
        expect(details['nativeDialTransportKinds'], [
          'network_unreachable',
          'dial_backoff',
        ]);
        expect(details['nativeDialAllTransient'], isFalse);
      }
    },
  );

  test(
    'failure flow ignores arbitrary native diagnostic fields and text',
    () async {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final result = await callP2PTurnCredentialsV1(
        _TurnCredentialBridge()
          ..response = {
            'ok': false,
            'errorCode': 'private-native-secret',
            'failureDiagnostic': {
              'stage': 'private-stage-secret',
              'kind': 'private-kind-secret',
              'dialCauseKind': 'private-cause-secret',
              'dialTransportKinds': ['private-address-secret'],
              'dialComplete': 'private-boolean-secret',
              'dialAttemptCount': 'private-count-secret',
              'message': 'private-raw-secret',
              'password': 'private-password-secret',
            },
          },
      );
      expect(result['errorCode'], 'TURN_CREDENTIALS_REJECTED');
      final details = events.last['details'] as Map;
      expect(details['nativeErrorCode'], 'unrecognized');
      expect(details.containsKey('nativeFailureStage'), isFalse);
      expect(jsonEncode(events), isNot(contains('private-')));
    },
  );

  test(
    'actual Go bridge preserves native diagnostics through sanitization',
    () async {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('com.mknoon/go_bridge');
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      for (final mode in ['rejected', 'platform']) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'relayTurnCredentialsV1');
          if (mode == 'platform') throw PlatformException(code: 'unavailable');
          return jsonEncode({
            'ok': false,
            'errorCode': 'TURN_CREDENTIALS_REJECTED',
            'errorMessage': 'Credential retrieval rejected',
            'failureDiagnostic': {
              'stage': 'new_stream',
              'kind': 'dial_backoff',
            },
          });
        });
        final result = await callP2PTurnCredentialsV1(GoBridgeClient());
        expect(result['errorCode'], 'TURN_CREDENTIALS_REJECTED');
        final details =
            events.lastWhere(
                  (e) => e['event'] == 'P2P_TURN_CREDENTIALS_V1_RESPONSE',
                )['details']
                as Map;
        expect(
          details['nativeErrorCode'],
          mode == 'platform' ? 'PLATFORM_ERROR' : 'TURN_CREDENTIALS_REJECTED',
        );
        if (mode == 'rejected') {
          expect(details['nativeFailureStage'], 'new_stream');
          expect(details['nativeFailureKind'], 'dial_backoff');
        }
      }
    },
  );

  test(
    'oversized diagnostic aggregates are omitted and exceptions have fixed stages',
    () async {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));
      await callP2PTurnCredentialsV1(
        _TurnCredentialBridge()
          ..response = {
            'ok': false,
            'errorCode': 'TURN_CREDENTIALS_REJECTED',
            'failureDiagnostic': {
              'dialTransportKinds': List.filled(9, 'unknown'),
              'dialAttemptCount': 100,
              'dialTruncated': true,
            },
          },
      );
      final details = events.last['details'] as Map;
      expect(details.containsKey('nativeDialTransportKinds'), isFalse);
      expect(details.containsKey('nativeDialAttemptCount'), isFalse);
      expect(details['nativeDialTruncated'], isTrue);
      for (final sample in [
        (
          _TurnCredentialBridge()..rawResponse = '{private-malformed',
          'bridge_format',
        ),
        (
          _TurnCredentialBridge()..error = StateError('private-exception'),
          'bridge_exception',
        ),
      ]) {
        final result = await callP2PTurnCredentialsV1(sample.$1);
        expect(result['ok'], isFalse);
        expect((events.last['details'] as Map)['responseStage'], sample.$2);
      }
      expect(jsonEncode(events), isNot(contains('private-')));
    },
  );

  test(
    'local failure logging cannot replace the typed bridge result',
    () async {
      debugSetFlowEventSink((event) {
        if (event['event'] == 'P2P_TURN_CREDENTIALS_V1_RESPONSE') {
          throw StateError('diagnostic-sink-failed');
        }
      });
      addTearDown(() => debugSetFlowEventSink(null));
      for (final sample in [
        (
          _TurnCredentialBridge()..rawResponse = '{malformed',
          'TURN_CREDENTIALS_INVALID_RESPONSE',
        ),
        (
          _TurnCredentialBridge()..error = StateError('native-error'),
          'TURN_CREDENTIALS_REJECTED',
        ),
      ]) {
        expect(
          (await callP2PTurnCredentialsV1(sample.$1))['errorCode'],
          sample.$2,
        );
      }
    },
  );

  test(
    'legacy ambiguous native outage is not permission for direct fallback',
    () async {
      final legacy = _TurnCredentialBridge()
        ..response = {'ok': false, 'errorCode': 'TURN_CREDENTIALS_UNAVAILABLE'};
      final classified = _TurnCredentialBridge()
        ..response = {'ok': false, 'errorCode': 'TURN_CREDENTIALS_TRANSIENT'};
      expect(
        (await callP2PTurnCredentialsV1(legacy))['errorCode'],
        'TURN_CREDENTIALS_REJECTED',
      );
      expect(
        (await callP2PTurnCredentialsV1(classified))['errorCode'],
        'TURN_CREDENTIALS_UNAVAILABLE',
      );
    },
  );

  test(
    'credential rejection and malformed JSON are never temporary outages',
    () async {
      for (final bridge in [
        _TurnCredentialBridge()
          ..response = {
            'ok': false,
            'errorCode': 'TURN_CREDENTIALS_UNAUTHORIZED',
          },
        _TurnCredentialBridge()
          ..response = {'ok': false, 'errorCode': 'NOT_INITIALIZED'},
        _TurnCredentialBridge()
          ..error = PlatformException(code: 'trust_failed', message: 'private'),
        _TurnCredentialBridge()..rawResponse = '{private malformed',
      ]) {
        final result = await callP2PTurnCredentialsV1(bridge);
        expect(result['ok'], isFalse);
        expect(result['errorCode'], isNot('TURN_CREDENTIALS_UNAVAILABLE'));
        expect(jsonEncode(result), isNot(contains('private')));
      }
    },
  );

  test(
    'opt-in TURN metadata uses its dedicated command and preserves validation',
    () async {
      final bridge = _TurnCredentialBridge()
        ..response = {'ok': false, 'errorCode': 'TURN_CREDENTIALS_TRANSIENT'};
      const diagnostics = <String, Object?>{
        'traceId': '11111111-2222-4333-8444-555555555555',
        'requestId': '22222222-2222-4333-8444-555555555555',
      };
      final result = await callP2PTurnCredentialsV1(
        bridge,
        diagnostics: diagnostics,
      );
      expect(bridge.request, <String, Object?>{
        'cmd': 'turn_credentials_with_diagnostics_v1',
        'payload': <String, Object?>{'diagnostics': diagnostics},
      });
      expect(result['ok'], isFalse);
      expect(result['errorCode'], 'TURN_CREDENTIALS_UNAVAILABLE');
      expect(result.containsKey('password'), isFalse);
    },
  );

  test(
    'VC2-01 sends the exact action-only command and validates the canonical bundle',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      final previousLogging = flowEventLoggingEnabled;
      flowEventLoggingEnabled = false;
      debugSetFlowEventSink(
        (event) => flowEvents.add(Map<String, dynamic>.from(event)),
      );
      addTearDown(() {
        debugSetFlowEventSink(null);
        flowEventLoggingEnabled = previousLogging;
      });
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final bridge = _TurnCredentialBridge()
        ..response = <String, dynamic>{
          'ok': true,
          'schema': 'turn_credentials',
          'version': 1,
          'urls': <String>[
            'turn:relay.invalid:3478?transport=udp',
            'turn:relay.invalid:3478?transport=tcp',
            'turns:relay.invalid:443?transport=tcp',
          ],
          'username': 'synthetic-user-never-log',
          'password': 'synthetic-password-never-log',
          'ttlSeconds': 600,
          'expiresAtMs': nowMs + 600000,
          'serverTimeMs': nowMs,
        };

      final result = await callP2PTurnCredentialsV1(bridge);

      expect(
        bridge.request?.length == 1 &&
            bridge.request?['cmd'] == 'relay:turn_credentials_v1' &&
            !bridge.request!.containsKey('payload'),
        isTrue,
        reason: 'credential request must be a no-payload action',
      );
      expect(
        result['ok'] == true &&
            result['schema'] == 'turn_credentials' &&
            result['version'] == 1 &&
            result['username'] == 'synthetic-user-never-log' &&
            result['password'] == 'synthetic-password-never-log' &&
            result['ttlSeconds'] == 600 &&
            result['expiresAtMs'] == nowMs + 600000 &&
            result['serverTimeMs'] == nowMs,
        isTrue,
        reason: 'canonical credential fields must survive bridge decoding',
      );
      expect(
        result['urls'],
        orderedEquals(<String>[
          'turn:relay.invalid:3478?transport=udp',
          'turn:relay.invalid:3478?transport=tcp',
          'turns:relay.invalid:443?transport=tcp',
        ]),
      );
      for (final key in <String>[
        'peerId',
        'from',
        'to',
        'staticPassword',
        'sharedSecret',
      ]) {
        expect(result.containsKey(key), isFalse);
      }
      final diagnostics = jsonEncode(flowEvents);
      expect(diagnostics.contains('synthetic-user-never-log'), isFalse);
      expect(diagnostics.contains('synthetic-password-never-log'), isFalse);
      expect(diagnostics.contains('turn:relay.invalid'), isFalse);
    },
  );

  test(
    'VC2-01 rejects malformed expired and skewed responses without echo or fallback',
    () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final invalidResponses = <Map<String, dynamic>>[
        <String, dynamic>{
          'ok': true,
          'schema': 'wrong',
          'version': 1,
          'urls': <String>['turn:relay.invalid:3478?transport=udp'],
          'username': 'synthetic-user-never-log',
          'password': 'synthetic-password-never-log',
          'ttlSeconds': 600,
          'expiresAtMs': nowMs + 600000,
          'serverTimeMs': nowMs,
        },
        <String, dynamic>{
          'ok': true,
          'schema': 'turn_credentials',
          'version': 1,
          'urls': <String>['turn:relay.invalid:3478?transport=udp'],
          'username': 'synthetic-user-never-log',
          'password': 'synthetic-password-never-log',
          'ttlSeconds': 600,
          'expiresAtMs': nowMs - 1,
          'serverTimeMs': nowMs - 600000,
        },
        <String, dynamic>{
          'ok': true,
          'schema': 'turn_credentials',
          'version': 1,
          'urls': <String>['turn:relay.invalid:3478?transport=udp'],
          'username': 'synthetic-user-never-log',
          'password': 'synthetic-password-never-log',
          'ttlSeconds': 600,
          'expiresAtMs': nowMs + 7200000,
          'serverTimeMs': nowMs + 3600000,
        },
        <String, dynamic>{
          'ok': true,
          'schema': 'turn_credentials',
          'version': 1,
          'urls': <String>[
            'turn:fixture-user@relay.invalid:3478?transport=udp',
          ],
          'username': 'synthetic-user-never-log',
          'password': 'synthetic-password-never-log',
          'ttlSeconds': 600,
          'expiresAtMs': nowMs + 600000,
          'serverTimeMs': nowMs,
        },
        <String, dynamic>{
          'ok': true,
          'schema': 'turn_credentials',
          'version': 1,
          'urls': <String>['turn::3478?transport=udp'],
          'username': 'synthetic-user-never-log',
          'password': 'synthetic-password-never-log',
          'ttlSeconds': 600,
          'expiresAtMs': nowMs + 600000,
          'serverTimeMs': nowMs,
        },
      ];

      for (final response in invalidResponses) {
        final bridge = _TurnCredentialBridge()..response = response;
        final result = await callP2PTurnCredentialsV1(bridge);
        final encoded = jsonEncode(result);
        expect(
          result['ok'] == false &&
              result['unsupported'] == false &&
              result['errorCode'] == 'TURN_CREDENTIALS_INVALID_RESPONSE' &&
              !result.containsKey('urls') &&
              !result.containsKey('username') &&
              !result.containsKey('password'),
          isTrue,
          reason: 'invalid credentials must fail closed without fallback',
        );
        expect(encoded.contains('synthetic-user-never-log'), isFalse);
        expect(encoded.contains('synthetic-password-never-log'), isFalse);
        expect(encoded.contains(jsonEncode(response)), isFalse);
      }
    },
  );

  test(
    'VC2-01 distinguishes old-relay unsupported from finite failure',
    () async {
      final oldRelay = _TurnCredentialBridge()
        ..response = <String, dynamic>{
          'ok': false,
          'errorCode': 'TURN_CREDENTIALS_UNSUPPORTED',
          'errorMessage': 'Relay does not support credential action',
        };
      final unsupported = await callP2PTurnCredentialsV1(oldRelay);
      expect(
        unsupported['ok'] == false && unsupported['unsupported'] == true,
        isTrue,
      );

      final limitedRelay = _TurnCredentialBridge()
        ..response = <String, dynamic>{
          'ok': false,
          'errorCode': 'TURN_CREDENTIALS_TRANSIENT',
          'errorMessage': 'Credential mint temporarily unavailable',
          'retryAfterMs': 2500,
        };
      final finite = await callP2PTurnCredentialsV1(limitedRelay);
      expect(
        finite['ok'] == false &&
            finite['unsupported'] == false &&
            finite['errorCode'] == 'TURN_CREDENTIALS_UNAVAILABLE' &&
            finite['retryAfterMs'] == 2500,
        isTrue,
      );
      expect(finite.containsKey('urls'), isFalse);
      expect(finite.containsKey('password'), isFalse);
    },
  );

  test(
    'relay:turn_credentials_v1 maps to relayTurnCredentialsV1 with no native arguments',
    () async {
      MethodCall? captured;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.mknoon/go_bridge'),
        (call) async {
          captured = call;
          return jsonEncode(<String, dynamic>{
            'ok': false,
            'errorCode': 'TURN_CREDENTIALS_UNAVAILABLE',
          });
        },
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('com.mknoon/go_bridge'),
          null,
        );
      });

      final client = GoBridgeClient();
      await client.send(
        jsonEncode(<String, dynamic>{'cmd': 'relay:turn_credentials_v1'}),
      );

      expect(captured?.method, 'relayTurnCredentialsV1');
      expect(captured?.arguments, isNull);
    },
  );
}
