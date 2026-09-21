import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../../integration_test/scripts/routing_stage_handshake.dart';

void main() {
  test(
    'unregister acknowledgment precedes app consumption; both stages bind',
    () async {
      final commands = <String>[];
      final pending = Completer<Map<String, dynamic>>();
      final host = await RoutingStageHost.start(
        run: 'run',
        target: 'sim',
        peerCommand: (cmd) async {
          commands.add(cmd);
          return cmd == 'unregister'
              ? pending.future
              : {'ok': true, 'namespace': 'test'};
        },
      );
      addTearDown(host.close);
      final events = <String>[];
      Future<void> request(String stage) => routingStageRequest(
        stage,
        endpoint: host.endpoint,
        secret: host.secret,
        run: host.run,
        target: host.target,
        emit: (s) => events.add(jsonEncode({'type': 'print', 'message': s})),
      );
      final app = request('R-Sim-3');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(commands, ['unregister']);
      expect(host.consumed, isEmpty);
      expect(events, isEmpty);
      pending.complete({'ok': true, 'namespace': 'test'});
      await app;
      await request('R-Sim-3-restore');
      await request('R-Sim-7-stop');
      await request('R-Sim-7-restart');
      host.requireConsumed(events.join('\n'));
      expect(commands, ['unregister', 'register', 'stop', 'start']);
      expect(() => host.requireConsumed(''), throwsStateError);
      expect(
        () => host.requireConsumed([...events, events.first].join('\n')),
        throwsStateError,
      );
      await expectLater(request('R-Sim-3'), throwsStateError);
    },
  );

  test(
    'bad bindings, secret and out-of-order requests never invoke CLI',
    () async {
      var commands = 0;
      final host = await RoutingStageHost.start(
        run: 'current',
        target: 'owned',
        peerCommand: (cmd) async {
          commands++;
          return {'ok': true, 'namespace': 'test'};
        },
      );
      addTearDown(host.close);
      for (final values in [
        ['old', 'owned', host.secret, 'R-Sim-3'],
        ['current', 'foreign', host.secret, 'R-Sim-3'],
        ['current', 'owned', 'wrong', 'R-Sim-3'],
        ['current', 'owned', host.secret, 'R-Sim-3-restore'],
      ]) {
        await expectLater(
          routingStageRequest(
            values[3],
            endpoint: host.endpoint,
            run: values[0],
            target: values[1],
            secret: values[2],
          ),
          throwsStateError,
        );
      }
      expect(commands, 0);
    },
  );

  test(
    'negative unregister acknowledgment never produces a consumption',
    () async {
      for (final ack in [
        {'ok': false},
        {'ok': true},
        {'ok': true, 'namespace': ''},
      ]) {
        final host = await RoutingStageHost.start(
          run: 'r',
          target: 't',
          peerCommand: (_) async => ack,
        );
        try {
          await expectLater(
            routingStageRequest(
              'R-Sim-3',
              endpoint: host.endpoint,
              secret: host.secret,
              run: 'r',
              target: 't',
            ),
            throwsStateError,
          );
          expect(host.consumed, isEmpty);
        } finally {
          await host.close();
        }
      }
    },
  );

  test(
    'wrong response binding and bounded absence cannot be consumed',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) async {
        final data = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
        r.response.write(jsonEncode({...data, 'ok': true, 'nonce': 'stale'}));
        await r.response.close();
      });
      await expectLater(
        routingStageRequest(
          'R-Sim-3',
          endpoint: 'http://127.0.0.1:${server.port}',
          secret: 's',
          run: 'r',
          target: 't',
        ),
        throwsStateError,
      );
      await expectLater(routingStageRequest('R-Sim-3'), throwsStateError);
      final host = await RoutingStageHost.start(
        run: 'r',
        target: 't',
        peerCommand: (_) => Completer<Map<String, dynamic>>().future,
      );
      addTearDown(host.close);
      await expectLater(
        routingStageRequest(
          'R-Sim-3',
          endpoint: host.endpoint,
          secret: host.secret,
          run: 'r',
          target: 't',
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(host.consumed, isEmpty);
    },
  );
}
