import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const _privateCanary = '/private/receiver-photo secret-key=private-canary';

final class _BlobBridge extends Bridge {
  _BlobBridge(this.respond);

  final Future<String> Function() respond;
  Map<String, dynamic>? request;

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
    return respond();
  }
}

Future<String> _decrypt(Bridge bridge, {Duration? timeout}) => callBlobDecrypt(
  bridge,
  filePath: '/private/ciphertext',
  keyBase64: 'private-key',
  nonce: 'private-nonce',
  timeout: timeout ?? const Duration(seconds: 1),
);

Matcher _safeOperational(String code) => allOf(
  isA<Exception>(),
  isNot(isA<StateError>()),
  predicate<Object>(
    (error) =>
        error.toString().contains(code) &&
        !error.toString().contains(_privateCanary),
    'an operational failure with only a safe classification',
  ),
);

void main() {
  group('callBlobDecrypt classification', () {
    for (final code in <String>[
      'DECRYPT_AUTH_ERROR',
      'DECRYPT_METADATA_ERROR',
    ]) {
      test(
        '$code keeps permanent crypto rejection without native details',
        () async {
          final bridge = _BlobBridge(
            () async => jsonEncode({
              'ok': false,
              'errorCode': code,
              'errorMessage': _privateCanary,
            }),
          );

          await expectLater(
            _decrypt(bridge),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'safe message',
                'blob:decrypt failed: $code',
              ),
            ),
          );
        },
      );
    }

    for (final code in <String>[
      'DECRYPT_IO_ERROR',
      'DECRYPT_ERROR',
      'INVALID_INPUT',
      'INTERNAL_ERROR',
      'NOT_INITIALIZED',
    ]) {
      test(
        '$code remains operational and cannot trigger StateError quarantine',
        () async {
          final bridge = _BlobBridge(
            () async => jsonEncode({
              'ok': false,
              'errorCode': code,
              'errorMessage': _privateCanary,
            }),
          );

          await expectLater(_decrypt(bridge), throwsA(_safeOperational(code)));
        },
      );
    }

    test('unknown native code cannot expose private values', () async {
      final bridge = _BlobBridge(
        () async => jsonEncode({
          'ok': false,
          'errorCode': _privateCanary,
          'errorMessage': _privateCanary,
        }),
      );

      await expectLater(
        _decrypt(bridge),
        throwsA(_safeOperational('UNKNOWN_ERROR')),
      );
    });

    for (final entry in <({String name, String response})>[
      (name: 'invalid JSON', response: _privateCanary),
      (name: 'non-object JSON', response: '[]'),
      (
        name: 'missing disposition',
        response: '{"errorCode":"DECRYPT_AUTH_ERROR"}',
      ),
      (name: 'missing success path', response: '{"ok":true}'),
      (name: 'empty success path', response: '{"ok":true,"decryptedPath":""}'),
      (
        name: 'non-string success path',
        response: '{"ok":true,"decryptedPath":7}',
      ),
    ]) {
      test('${entry.name} is operational, not a ciphertext verdict', () async {
        final bridge = _BlobBridge(() async => entry.response);
        await expectLater(
          _decrypt(bridge),
          throwsA(_safeOperational('MALFORMED_RESPONSE')),
        );
      });
    }

    test(
      'transport-thrown StateError cannot impersonate authenticated rejection',
      () async {
        final bridge = _BlobBridge(
          () async => throw StateError(_privateCanary),
        );
        await expectLater(
          _decrypt(bridge),
          throwsA(_safeOperational('BRIDGE_UNAVAILABLE')),
        );
      },
    );

    test('timeout remains a safe operational failure', () async {
      final bridge = _BlobBridge(() => Completer<String>().future);
      await expectLater(
        _decrypt(bridge, timeout: const Duration(milliseconds: 1)),
        throwsA(_safeOperational('BRIDGE_TIMEOUT')),
      );
    });

    test('success preserves the request and native output path', () async {
      const output = '/private/decrypted-photo';
      final bridge = _BlobBridge(
        () async => jsonEncode({'ok': true, 'decryptedPath': output}),
      );

      expect(await _decrypt(bridge), output);
      expect(bridge.request, <String, dynamic>{
        'cmd': 'blob:decrypt',
        'payload': <String, dynamic>{
          'filePath': '/private/ciphertext',
          'keyBase64': 'private-key',
          'nonce': 'private-nonce',
        },
      });
    });
  });
}
