import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _limit = Duration(seconds: 3);
const _method = MethodChannel('com.mknoon/go_bridge');
const _events = MethodChannel('com.mknoon/go_bridge_events');
const _account = '12D3KooWJsEmQWn5WGGn9AZX79emq3RkGNx2ihFwWzZAqbiUQGMF';

Map<String, Object?> _request(String op) => {
  'version': 1,
  'revision': 1,
  'consentEpoch': 1,
  'profileBinding':
      'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'accountPeerId': _account,
  'op': op,
  if (op == 'configure') ...{
    'enabled': true,
    'statePath': '/synthetic/activity-state.json',
    'rootPrivateKeyBase64': 'SYNTHETIC_PRIVATE_KEY',
    'preservePendingOnUnarm': false,
  },
  if (op == 'markWeekly') ...{
    'week': '2026-W47',
    'kinds': ['group'],
  },
};

Map<String, dynamic> _projection({bool springWeek = false}) => {
  'ok': true,
  'data': {
    'revision': 1,
    'consentEpoch': 1,
    'weekly': {
      'week': springWeek ? '2026-W13' : '2026-W47',
      'startUnixMillis': springWeek ? 1774220400000 : 1794783600000,
      'endUnixMillis': springWeek ? 1774821600000 : 1795388400000,
      'kinds': ['active', 'group'],
      'acknowledged': [
        {
          'relayPeerId': _account,
          'kinds': ['group'],
        },
      ],
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoBridgeClient client;
  late Map<String, dynamic> response;
  final requests = <Map<String, dynamic>>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    client = GoBridgeClient();
    response = _projection();
    requests.clear();
    messenger.setMockMethodCallHandler(_events, (_) async => null);
    messenger.setMockMethodCallHandler(_method, (call) async {
      expect(call.method, 'activeIdentityReporterV1');
      requests.add(jsonDecode(call.arguments as String) as Map<String, dynamic>);
      return jsonEncode(response);
    });
    await client.initialize().timeout(_limit);
  });

  tearDown(() async {
    client.dispose();
    await Future<void>.delayed(Duration.zero).timeout(_limit);
    messenger.setMockMethodCallHandler(_method, null);
    messenger.setMockMethodCallHandler(_events, null);
  });

  Future<Map<String, dynamic>> send(String op) async =>
      jsonDecode(
            await client
                .send(
                  jsonEncode({
                    'cmd': 'active_identity_reporter_v1',
                    'payload': _request(op),
                  }),
                )
                .timeout(_limit),
          )
          as Map<String, dynamic>;

  for (final springWeek in [false, true]) {
    test('B15WA projection traverses real Dart adapter DST=$springWeek', () async {
      response = _projection(springWeek: springWeek);
      expect(await send('weeklyProjection').timeout(_limit), response);
      expect(requests, [_request('weeklyProjection')]);
    });
  }

  test('B15WA weekly mark preserves its bounded kinds and receipt', () async {
    response = {
      'ok': true,
      'data': {'revision': 1, 'consentEpoch': 1, 'accepted': true},
    };
    expect(await send('markWeekly').timeout(_limit), response);
    expect(requests, [_request('markWeekly')]);
  });

  for (final sample in const [
    (op: 'configure', field: 'configured'),
    (op: 'mark', field: 'accepted'),
    (op: 'flush', field: 'queued'),
  ]) {
    test('B15WA legacy ${sample.op} receipt remains unchanged', () async {
      response = {
        'ok': true,
        'data': {'revision': 1, 'consentEpoch': 1, sample.field: true},
      };
      expect(await send(sample.op).timeout(_limit), response);
    });
  }

  final malformed = <String, void Function(Map<String, dynamic>)>{
    'Boolean interval': (value) {
      value['data']['weekly']['startUnixMillis'] = true;
    },
    'minInt64 interval': (value) {
      value['data']['weekly']['startUnixMillis'] = -9223372036854775808;
      value['data']['weekly']['endUnixMillis'] = 0;
    },
    'extra nested key': (value) {
      value['data']['weekly']['private'] = 'not a weekly field';
    },
    'duplicate kind': (value) {
      value['data']['weekly']['kinds'] = ['group', 'group'];
    },
    'reversed interval': (value) {
      value['data']['weekly']['endUnixMillis'] = 0;
    },
    'empty acknowledged kind': (value) {
      value['data']['weekly']['acknowledged'][0]['kinds'] = <String>[];
    },
  };
  for (final sample in malformed.entries) {
    test('B15WA refuses ${sample.key}', () async {
      sample.value(response);
      expect(
        await send('weeklyProjection').timeout(_limit),
        containsPair('ok', false),
      );
    });
  }

  test('B15WA disposal refuses a held native projection', () async {
    final entered = Completer<void>();
    final release = Completer<String>();
    messenger.setMockMethodCallHandler(_method, (_) {
      entered.complete();
      return release.future;
    });
    final pending = send('weeklyProjection');
    try {
      await entered.future.timeout(_limit);
      client.dispose();
      release.complete(jsonEncode(response));
      expect(await pending.timeout(_limit), containsPair('ok', false));
    } finally {
      if (!release.isCompleted) release.complete(jsonEncode(response));
      await pending.timeout(_limit);
    }
  });
}
