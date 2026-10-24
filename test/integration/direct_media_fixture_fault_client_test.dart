import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/direct_media_fixture_fault_client.dart';

void main() {
  late HttpServer server;
  late List<({String method, String path, String query, String body})> seen;
  late int nextStatus;
  late Object nextBody;

  setUp(() async {
    seen = [];
    nextStatus = 200;
    nextBody = <String, Object?>{'schema': 'mknoon.h2.direct-media-fault.v1'};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      seen.add((
        method: request.method,
        path: request.uri.path,
        query: request.uri.query,
        body: await utf8.decodeStream(request),
      ));
      request.response
        ..statusCode = nextStatus
        ..headers.contentType = ContentType.json
        ..write(nextBody is String ? nextBody : jsonEncode(nextBody));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  DirectMediaFixtureFaultClient client() => DirectMediaFixtureFaultClient(
    Uri.parse('http://127.0.0.1:${server.port}/${'a' * 64}'),
  );

  test('posts a targeted fault to the capability path', () async {
    nextBody = <String, Object?>{
      'schema': 'mknoon.h2.direct-media-fault.v1',
      'op': 'remove',
      'status': {'present': false, 'hashMatches': false},
    };
    final status = await client().apply(
      DirectMediaFixtureFaultOp.remove,
      recipientPeerId: 'peer-1',
      attachmentId: 'att-1',
    );

    expect(seen.single.method, 'POST');
    expect(seen.single.path, '/${'a' * 64}/fault');
    expect(jsonDecode(seen.single.body), {
      'op': 'remove',
      'recipientPeerId': 'peer-1',
      'attachmentId': 'att-1',
    });
    expect(status, {'present': false, 'hashMatches': false});
  });

  test('clock faults carry no target', () async {
    await client().apply(DirectMediaFixtureFaultOp.expire);
    await client().apply(DirectMediaFixtureFaultOp.clockReset);

    expect(seen.map((r) => jsonDecode(r.body)), [
      {'op': 'expire'},
      {'op': 'clock_reset'},
    ]);
  });

  test('expire may name a legacy target', () async {
    await client().apply(
      DirectMediaFixtureFaultOp.expire,
      recipientPeerId: 'peer-1',
      attachmentId: 'att-9',
    );

    expect(jsonDecode(seen.single.body), {
      'op': 'expire',
      'recipientPeerId': 'peer-1',
      'attachmentId': 'att-9',
    });
  });

  test('targeted ops without a target are refused before any request', () {
    expect(
      () => client().apply(DirectMediaFixtureFaultOp.corrupt),
      throwsArgumentError,
    );
    expect(seen, isEmpty);
  });

  test('a refused fault surfaces the relay reason', () async {
    nextStatus = 409;
    nextBody = 'no pending custody entry to remove\n';

    await expectLater(
      client().apply(
        DirectMediaFixtureFaultOp.remove,
        recipientPeerId: 'peer-1',
        attachmentId: 'gone',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'fault remove refused (409): no pending custody entry to remove',
        ),
      ),
    );
  });

  test('lists pending targets oldest first', () async {
    nextBody = <String, Object?>{
      'schema': 'mknoon.h2.direct-media-fault.v1',
      'pending': [
        {
          'op': '',
          'recipientPeerId': 'peer-1',
          'attachmentId': 'att-1',
          'lane': 'legacy',
        },
        {
          'op': '',
          'recipientPeerId': 'peer-1',
          'attachmentId': 'att-2',
          'lane': 'custody',
        },
      ],
    };

    final pending = await client().pending();

    expect(seen.single.method, 'GET');
    expect(seen.single.query, 'list=pending');
    expect(pending, [
      (recipientPeerId: 'peer-1', attachmentId: 'att-1', lane: 'legacy'),
      (recipientPeerId: 'peer-1', attachmentId: 'att-2', lane: 'custody'),
    ]);
  });
}
