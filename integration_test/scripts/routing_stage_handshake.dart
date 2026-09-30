import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

String routingNonce() => base64Url.encode(
  List<int>.generate(32, (_) => Random.secure().nextInt(256)),
);

/// Loopback control channel for iOS simulator/desktop or pinned adb reverse. The secret
/// is compiled into this one test invocation, never an ambient file. Android
/// receives a fresh device-scoped reverse mapping. Physical iOS is unsupported.
class RoutingStageHost {
  RoutingStageHost._(this.server, this.run, this.target, this.peerCommand);
  final HttpServer server;
  final String run;
  final String target;
  final Future<Map<String, dynamic>> Function(String) peerCommand;
  final String secret = routingNonce();
  final Map<String, String> _issued = {};
  final Set<String> consumed = {};
  final Set<String> _requested = {};
  bool _busy = false;
  static const stages = [
    'R-Sim-3',
    'R-Sim-3-restore',
    'R-Sim-7-stop',
    'R-Sim-7-restart',
  ];

  static Future<RoutingStageHost> start({
    required String run,
    required String target,
    required Future<Map<String, dynamic>> Function(String) peerCommand,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final host = RoutingStageHost._(server, run, target, peerCommand);
    server.listen(host._handle);
    return host;
  }

  String? forwardedEndpoint;
  String get endpoint => forwardedEndpoint ?? 'http://127.0.0.1:${server.port}';
  List<String> get defines => [
    'ROUTING_STAGE_URL=$endpoint',
    'ROUTING_STAGE_SECRET=$secret',
    'ROUTING_STAGE_RUN=$run',
    'ROUTING_STAGE_TARGET=$target',
  ];

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method != 'POST' ||
          request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $secret') {
        throw StateError('unauthenticated stage request');
      }
      final body = await utf8.decoder
          .bind(request)
          .join()
          .timeout(const Duration(seconds: 5));
      if (body.length > 4096) throw StateError('oversized stage request');
      final data = jsonDecode(body) as Map<String, dynamic>;
      final stage = data['stage'];
      if (data['run'] != run ||
          data['target'] != target ||
          !stages.contains(stage) ||
          data['nonce'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}=$').hasMatch(data['nonce'] as String)) {
        throw StateError('wrong stage binding');
      }
      final nonce = data['nonce'] as String;
      if (request.uri.path == '/request') {
        if (_busy ||
            _requested.contains(stage) ||
            (stages.indexOf(stage as String) > 0 &&
                !consumed.contains(stages[stages.indexOf(stage) - 1]))) {
          throw StateError('duplicate or out-of-order request');
        }
        _busy = true;
        _requested.add(stage);
        try {
          final command = {
            'R-Sim-3': 'unregister',
            'R-Sim-3-restore': 'register',
            'R-Sim-7-stop': 'stop',
            'R-Sim-7-restart': 'start',
          }[stage]!;
          final ack = await peerCommand(
            command,
          ).timeout(const Duration(seconds: 60));
          if (ack['ok'] != true ||
              ((command == 'register' || command == 'unregister') &&
                  (ack['namespace'] is! String ||
                      (ack['namespace'] as String).isEmpty))) {
            throw StateError(
              'CLI did not acknowledge the rendezvous operation',
            );
          }
          _issued[stage] = nonce;
        } finally {
          _busy = false;
        }
      } else if (request.uri.path == '/consumed') {
        if (_issued[stage] != nonce || !consumed.add(stage as String)) {
          throw StateError('unissued or replayed consumption');
        }
      } else {
        throw StateError('unknown stage endpoint');
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({...data, 'ok': true}));
    } catch (_) {
      request.response.statusCode = HttpStatus.conflict;
      request.response.write('Stage handshake rejected');
    } finally {
      await request.response.close();
    }
  }

  void requireConsumed(String output) {
    for (final stage in stages) {
      final marker =
          'ROUTING_STAGE_CONSUMED $run $target $stage ${_issued[stage]}';
      // A server receipt alone is insufficient: require the app's matching
      // current-run print event after it validates and consumes the response.
      final count = output.split('\n').where((line) {
        try {
          final event = jsonDecode(line);
          return event is Map &&
              event['type'] == 'print' &&
              event['message'] == marker;
        } catch (_) {
          return false;
        }
      }).length;
      if (!consumed.contains(stage) || count != 1) {
        throw StateError('Missing current-run app consumption for $stage');
      }
    }
  }

  Future<void> close() => server.close(force: true);
}

/// Called at the actual stage boundary by the app. No signal can be accepted
/// until the host has received this fresh nonce and acknowledged CLI completion.
Future<void> routingStageRequest(
  String stage, {
  String endpoint = const String.fromEnvironment('ROUTING_STAGE_URL'),
  String secret = const String.fromEnvironment('ROUTING_STAGE_SECRET'),
  String run = const String.fromEnvironment('ROUTING_STAGE_RUN'),
  String target = const String.fromEnvironment('ROUTING_STAGE_TARGET'),
  Duration timeout = const Duration(seconds: 70),
  void Function(String) emit = print,
}) async {
  final uri = Uri.tryParse(endpoint);
  if (uri == null ||
      uri.scheme != 'http' ||
      uri.host != '127.0.0.1' ||
      secret.isEmpty ||
      run.isEmpty ||
      target.isEmpty) {
    throw StateError('[BLOCKED] R-Sim-3 requires a bound stage channel');
  }
  final nonce = routingNonce();
  final binding = {
    'run': run,
    'target': target,
    'stage': stage,
    'nonce': nonce,
  };
  final client = HttpClient()..connectionTimeout = timeout;
  Future<void> exchange(String path) async {
    final request = await client.postUrl(uri.replace(path: path));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(binding));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Stage request rejected');
    }
    final ack = jsonDecode(text) as Map<String, dynamic>;
    if (ack['ok'] != true ||
        binding.entries.any((e) => ack[e.key] != e.value)) {
      throw StateError('Stale or incorrectly bound stage acknowledgment');
    }
  }

  try {
    await (() async {
      await exchange('/request');
      await exchange('/consumed');
    })().timeout(timeout);
    emit('ROUTING_STAGE_CONSUMED $run $target $stage $nonce');
  } finally {
    client.close(force: true);
  }
}
