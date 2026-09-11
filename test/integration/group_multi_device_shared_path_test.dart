import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/group_multi_device_real_harness.dart';

void main() {
  tearDown(() {
    setGroupMultiDeviceRuntimeSharedDir(null);
  });

  group('strict group download observation', () {
    const privateValue = 'private-message-key-peer-and-path';
    Map<String, dynamic> request(String command) => <String, dynamic>{
      'cmd': command,
      'payload': <String, dynamic>{
        'id': privateValue,
        'custodyKind': 'group_media_blob_v1',
        'custodyContract': 'ack_or_expiry_v1',
        'contentHash': privateValue,
        'size': 32,
        'mime': 'application/octet-stream',
        'expiresAtMs': 1930000000000,
        'filePath': privateValue,
        'keyBase64': privateValue,
        'nonce': privateValue,
      },
    };
    Map<String, dynamic> success(String command) => command == 'media:download'
        ? <String, dynamic>{
            'ok': true,
            ...request(command)['payload'] as Map<String, dynamic>,
            'custodyRelayPeerId': privateValue,
          }
        : <String, dynamic>{'ok': true, 'decryptedPath': '$privateValue.dec'};
    Map<String, String> exchange(
      String command,
      Map<String, dynamic> response,
    ) => <String, String>{
      'request': jsonEncode(request(command)),
      'response': jsonEncode(response),
    };
    Map<String, Object> observe(List<Map<String, String>> exchanges) =>
        summarizeGroupMediaDownloadObservation(
          sentMessages: exchanges.map((item) => item['request']!).toList(),
          bridgeExchanges: exchanges,
          sentStart: 0,
          exchangeStart: 0,
        );

    test('exact receipt and decrypt path produce only closed facts', () {
      final result = observe(<Map<String, String>>[
        exchange('media:download', success('media:download')),
        exchange('blob:decrypt', success('blob:decrypt')),
      ]);
      expect(result['downloadRequests'], 1);
      expect(result['downloadResponses'], 1);
      expect(result['downloadOk'], isTrue);
      expect(result['receiptMatchesRequest'], isTrue);
      expect(result['decryptRequests'], 1);
      expect(result['decryptResponses'], 1);
      expect(result['decryptOk'], isTrue);
      expect(result['decryptPathMatchesRequest'], isTrue);
      expect(result['downloadErrorCode'], 'none');
      expect(result['decryptErrorCode'], 'none');
      expect(jsonEncode(result), isNot(contains(privateValue)));
    });

    for (final field in <String>[
      'id',
      'custodyKind',
      'custodyContract',
      'contentHash',
      'size',
      'mime',
      'expiresAtMs',
      'custodyRelayPeerId',
    ]) {
      test('changed receipt $field is rejected', () {
        final response = success('media:download');
        response[field] = field == 'custodyRelayPeerId' ? '  relay  ' : null;
        final result = observe(<Map<String, String>>[
          exchange('media:download', response),
        ]);
        expect(result['receiptMatchesRequest'], isFalse);
      });
    }

    test(
      'prior calls excluded and duplicate current calls saturate at two',
      () {
        final item = exchange('media:download', success('media:download'));
        final prior = exchange('blob:decrypt', success('blob:decrypt'));
        final result = summarizeGroupMediaDownloadObservation(
          sentMessages: <String>[
            prior['request']!,
            ...List.filled(4, item['request']!),
          ],
          bridgeExchanges: <Map<String, String>>[
            prior,
            ...List.filled(4, item),
          ],
          sentStart: 1,
          exchangeStart: 1,
        );
        expect(result['downloadRequests'], 2);
        expect(result['downloadResponses'], 2);
        expect(result['downloadOk'], isFalse);
        expect(result['receiptMatchesRequest'], isFalse);
        expect(result['downloadErrorCode'], 'ambiguous');
        expect(result['decryptRequests'], 0);
        expect(result['decryptResponses'], 0);
        expect(result['decryptErrorCode'], 'unobserved');
      },
    );

    test('one completed response cannot certify two current attempts', () {
      final item = exchange('media:download', success('media:download'));
      final result = summarizeGroupMediaDownloadObservation(
        sentMessages: <String>[item['request']!, item['request']!],
        bridgeExchanges: <Map<String, String>>[item],
        sentStart: 0,
        exchangeStart: 0,
      );
      expect(result['downloadRequests'], 2);
      expect(result['downloadResponses'], 1);
      expect(result['downloadOk'], isFalse);
      expect(result['receiptMatchesRequest'], isFalse);
      expect(result['downloadErrorCode'], 'ambiguous');
    });

    test('pending native response is distinct from a refusal', () {
      final result = summarizeGroupMediaDownloadObservation(
        sentMessages: <String>[jsonEncode(request('media:download'))],
        bridgeExchanges: const <Map<String, String>>[],
        sentStart: 0,
        exchangeStart: 0,
      );
      expect(result['downloadRequests'], 1);
      expect(result['downloadResponses'], 0);
      expect(result['downloadErrorCode'], 'unobserved');
    });

    test('native refusal is allowlisted and unknown errors remain private', () {
      final result = observe(<Map<String, String>>[
        exchange('media:download', <String, dynamic>{
          'ok': false,
          'errorCode': 'MEDIA_CUSTODY_NOT_AUTHORIZED',
          'message': privateValue,
        }),
        exchange('blob:decrypt', <String, dynamic>{
          'ok': false,
          'errorCode': privateValue,
          'error': privateValue,
        }),
      ]);
      expect(result['downloadErrorCode'], 'MEDIA_CUSTODY_NOT_AUTHORIZED');
      expect(result['decryptErrorCode'], 'unknown');
      expect(result['downloadOk'], isFalse);
      expect(jsonEncode(result), isNot(contains(privateValue)));
    });

    test(
      'wrong native decrypted path fails comparison without exposing it',
      () {
        final result = observe(<Map<String, String>>[
          exchange('blob:decrypt', <String, dynamic>{
            'ok': true,
            'decryptedPath': '$privateValue.other',
          }),
        ]);
        expect(result['decryptOk'], isTrue);
        expect(result['decryptPathMatchesRequest'], isFalse);
        expect(jsonEncode(result), isNot(contains(privateValue)));
      },
    );

    test('malformed response remains a closed label', () {
      final result = observe(<Map<String, String>>[
        <String, String>{
          'request': jsonEncode(request('media:download')),
          'response': privateValue,
        },
      ]);
      expect(result['downloadErrorCode'], 'malformed');
      expect(result['receiptMatchesRequest'], isFalse);
      expect(jsonEncode(result), isNot(contains(privateValue)));
    });
  });

  test('shared signal helpers use runtime shared directory override', () {
    final dir = Directory.systemTemp.createTempSync(
      'gmd_shared_dir_override_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    final proofName =
        'proof_${pid}_${DateTime.now().microsecondsSinceEpoch}.txt';

    setGroupMultiDeviceRuntimeSharedDir(dir.path);

    expect(groupMultiDeviceRuntimeSharedDir(), dir.path);
    expect(sharedPath(proofName), '${dir.path}/$proofName');

    writeSharedText(proofName, 'ok');

    expect(File('${dir.path}/$proofName').readAsStringSync(), 'ok');
    expect(File('/tmp/$proofName').existsSync(), isFalse);
  });

  test(
    'Android harness acquires the canonical runtime before Go bridge use',
    () {
      final source = File(
        'integration_test/group_multi_device_real_harness.dart',
      ).readAsStringSync();
      final leaseDeclaration = source.indexOf(
        'final runtimeLease = CanonicalRuntimeDeviceTestLease(',
      );
      final leaseAcquire = source.indexOf(
        'setUpAll(runtimeLease.acquire);',
        leaseDeclaration,
      );
      final scenarioTest = source.indexOf(
        "testWidgets(\n    'MD-004 multi-device proof",
        leaseAcquire,
      );

      expect(
        source,
        contains("import '_support/canonical_runtime_device_test_lease.dart';"),
      );
      expect(leaseDeclaration, isNonNegative);
      expect(leaseAcquire, greaterThan(leaseDeclaration));
      expect(scenarioTest, greaterThan(leaseAcquire));
      expect(source, contains('tearDownAll(runtimeLease.release);'));
    },
  );
}
