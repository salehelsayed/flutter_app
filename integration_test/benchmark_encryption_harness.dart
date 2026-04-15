/// Simulator Benchmark: Encryption Overhead (Test G)
///
/// Measures ML-KEM keygen, encrypt/decrypt latency with real Go crypto.
/// Run: flutter test integration_test/benchmark_encryption_harness.dart -d <DEVICE_ID>
@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';

import 'benchmark_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('G-Sim-1: ML-KEM keygen (10 iterations)', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: ML-KEM KEYGEN (G-Sim-1)');
    print('${'═' * 60}\n');

    final bridge = GoBridgeClient();
    await bridge.initialize();

    final timings = <int>[];

    for (var i = 0; i < 10; i++) {
      final sw = Stopwatch()..start();
      final response = await bridge.send(
        jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
      );
      sw.stop();

      final result = jsonDecode(response) as Map<String, dynamic>;
      expect(result['ok'], isTrue, reason: 'mlkem.keygen should succeed');
      timings.add(sw.elapsedMilliseconds);
    }

    timings.sort();
    printBenchmark(
      'sim_mlkem_keygen_ms',
      p50: percentile(timings, 50),
      p95: percentile(timings, 95),
      n: timings.length,
    );

    bridge.dispose();
  });

  testWidgets('G-Sim-2: Encrypt/decrypt with payload sizes', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: ENCRYPT/DECRYPT (G-Sim-2)');
    print('${'═' * 60}\n');

    final bridge = GoBridgeClient();
    await bridge.initialize();

    // Generate ML-KEM key pair
    final keyResponse = await bridge.send(
      jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
    );
    final keyResult = jsonDecode(keyResponse) as Map<String, dynamic>;
    expect(keyResult['ok'], isTrue);
    final publicKey = keyResult['publicKey'] as String;
    final secretKey = keyResult['secretKey'] as String;

    final sizes = {'100b': 100, '1kb': 1024, '10kb': 10240, '100kb': 102400};

    for (final entry in sizes.entries) {
      final label = entry.key;
      final size = entry.value;
      final payload = 'x' * size;

      // Encrypt
      final encSw = Stopwatch()..start();
      final encResponse = await bridge.send(
        jsonEncode({
          'cmd': 'message.encrypt',
          'payload': {
            'plaintext': payload,
            'recipientPublicKey': publicKey,
          },
        }),
      );
      encSw.stop();
      final encResult = jsonDecode(encResponse) as Map<String, dynamic>;
      expect(encResult['ok'], isTrue, reason: 'encrypt should succeed');

      // Decrypt
      final decSw = Stopwatch()..start();
      final decResponse = await bridge.send(
        jsonEncode({
          'cmd': 'message.decrypt',
          'payload': {
            'ciphertext': encResult['ciphertext'],
            'kem': encResult['kem'],
            'nonce': encResult['nonce'],
            'secretKey': secretKey,
          },
        }),
      );
      decSw.stop();
      final decResult = jsonDecode(decResponse) as Map<String, dynamic>;
      expect(decResult['ok'], isTrue, reason: 'decrypt should succeed');

      print('[BENCHMARK] sim_encrypt_${label}_ms = ${encSw.elapsedMilliseconds}ms');
      print('[BENCHMARK] sim_decrypt_${label}_ms = ${decSw.elapsedMilliseconds}ms');
    }

    bridge.dispose();
  });

  testWidgets('G-Sim-3: Group message encrypt+sign + decrypt', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: GROUP CRYPTO (G-Sim-3)');
    print('${'═' * 60}\n');

    // Group crypto requires two nodes in the same group — this test
    // collects timing from FLOW events when a group publish occurs.
    // Without a second node, we verify the encrypt side only.
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    // group.encrypt — measures group encryption timing
    final encSw = Stopwatch()..start();
    final encResponse = await node.bridge.send(
      jsonEncode({
        'cmd': 'group.encrypt',
        'payload': {
          'plaintext': 'group benchmark message',
          'groupKey': 'MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=',
        },
      }),
    );
    encSw.stop();
    final encResult = jsonDecode(encResponse) as Map<String, dynamic>;
    expect(encResult['ok'], isTrue, reason: 'group.encrypt should succeed');
    printBenchmarkSingle('sim_group_encrypt_ms', encSw.elapsedMilliseconds);

    // group.decrypt — measures group decryption timing
    final decSw = Stopwatch()..start();
    final decResponse = await node.bridge.send(
      jsonEncode({
        'cmd': 'group.decrypt',
        'payload': {
          'ciphertext': encResult['ciphertext'],
          'nonce': encResult['nonce'],
          'groupKey': 'MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=',
        },
      }),
    );
    decSw.stop();
    final decResult = jsonDecode(decResponse) as Map<String, dynamic>;
    expect(decResult['ok'], isTrue, reason: 'group.decrypt should succeed');
    printBenchmarkSingle('sim_group_decrypt_ms', decSw.elapsedMilliseconds);

    // §16: In a real two-node scenario, we'd also collect:
    //   group:publish_debug { encryptMs, signMs }
    //   group_message:received { decryptMs }
    print('[NOTE] Full group publish timing requires two-node orchestrator');

    await node.dispose();
  });
}
