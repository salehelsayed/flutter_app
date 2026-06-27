import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';

/// FDC-15 (receive leg) — `media:lan_received` must be ROUTED to a typed
/// consumer, never the unknown-event sink. `go_bridge_client_test.dart` is in
/// ONE_TO_ONE_TESTS, so an unrouted event that bumps `_unknownPushEventCount`
/// can regress the 1:1 gate — not merely fail to render.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String event(String name, Map<String, dynamic> data) =>
      jsonEncode({'event': name, 'data': data});

  test('TD8: media:lan_received routes to onLocalMediaReceived (not the '
      'unknown sink)', () {
    final client = GoBridgeClient();
    LocalMediaReady? received;
    client.onLocalMediaReceived = (m) => received = m;

    final unknownBefore = client.debugUnknownPushEventCountForTest;

    client.debugHandleEventForTest(
      event('media:lan_received', {
        'id': 'm1',
        'from': 'peer-1',
        'to': 'self',
        'mime': 'application/octet-stream',
        'size': 42,
        'localPath': '/tmp/go-staged.bin',
        'sha256': 'abc123',
        'enc': true,
        'encScheme': 'blob-aes-gcm-v1',
        'durationMs': 1500,
      }),
    );

    expect(received, isNotNull);
    expect(received!.id, 'm1');
    expect(received!.from, 'peer-1');
    expect(received!.localPath, '/tmp/go-staged.bin');
    expect(received!.sha256, 'abc123');
    expect(received!.enc, isTrue);
    expect(received!.encScheme, 'blob-aes-gcm-v1');
    // No unknown-event regression (the discriminator that protects the 1:1 gate).
    expect(client.debugUnknownPushEventCountForTest, unknownBefore);
  });

  test('TD8b (control): a genuinely-unknown event DOES bump the unknown sink',
      () {
    final client = GoBridgeClient();
    final before = client.debugUnknownPushEventCountForTest;
    client.debugHandleEventForTest(event('totally:unknown', const {}));
    expect(client.debugUnknownPushEventCountForTest, before + 1);
  });
}
