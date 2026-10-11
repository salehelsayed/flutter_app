import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/update_check/domain/version_file_verifier.dart';
import 'package:flutter_app/features/update_check/infrastructure/version_file_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_only_tls.dart';

/// Local HTTPS server (test-only self-signed certificate).
class _Server {
  _Server._(this.server);

  static Future<_Server> start() async {
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(testOnlyLocalhostCertPem))
      ..usePrivateKeyBytes(utf8.encode(testOnlyLocalhostKeyPem));
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final wrapper = _Server._(server);
    server.listen(wrapper._handle);
    return wrapper;
  }

  final HttpServer server;
  final List<HttpRequest> requests = [];
  final Map<String, Future<void> Function(HttpResponse)> routes = {};

  Uri url(String path) => Uri.parse('https://127.0.0.1:${server.port}$path');

  Future<void> _handle(HttpRequest request) async {
    requests.add(request);
    final route = routes[request.uri.path];
    final response = request.response;
    try {
      if (route == null) {
        response.statusCode = HttpStatus.notFound;
      } else {
        await route(response);
      }
      await response.close();
    } catch (_) {
      // The client hung up first (size limit or deadline).
    }
  }

  Future<void> close() => server.close(force: true);
}

HttpClient _trustTestCert() =>
    HttpClient()
      ..badCertificateCallback = (cert, host, port) => host == '127.0.0.1';

void main() {
  late _Server server;
  var factoryCalls = 0;

  VersionFileFetcher fetcher({Duration? deadline}) => VersionFileFetcher(
    clientFactory: () {
      factoryCalls++;
      return _trustTestCert();
    },
    deadline: deadline ?? const Duration(seconds: 5),
  );

  setUp(() async {
    server = await _Server.start();
    factoryCalls = 0;
  });

  tearDown(() => server.close());

  test('200 body is returned; only default headers are sent', () async {
    server.routes['/version.json'] = (r) async => r.write('{"v":1}');
    final bytes = await fetcher().fetch(server.url('/version.json'));
    expect(utf8.decode(bytes!), '{"v":1}');

    final request = server.requests.single;
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    // Printed for the SE-41 evidence (AC5).
    // ignore: avoid_print
    print('SE41_HEADERS_SENT ${jsonEncode(headers)}');
    // Host is required by HTTP/1.1. Nothing else beyond the two defaults.
    expect(headers.keys.toSet(), {'user-agent', 'accept-encoding', 'host'});
    expect(headers['accept-encoding'], 'gzip');
    expect(headers['user-agent'], startsWith('Dart/'));
    expect(headers.containsKey('cookie'), isFalse);
    expect(headers.containsKey('authorization'), isFalse);
    expect(request.uri.hasQuery, isFalse);
    expect(request.method, 'GET');
  });

  test('3xx is not followed and counts as a failed check', () async {
    server.routes['/version.json'] = (r) async {
      r.statusCode = HttpStatus.found;
      r.headers.set(
        HttpHeaders.locationHeader,
        server.url('/other').toString(),
      );
    };
    server.routes['/other'] = (r) async => r.write('{}');
    expect(await fetcher().fetch(server.url('/version.json')), isNull);
    expect(server.requests.map((r) => r.uri.path), ['/version.json']);
  });

  test('non-200 statuses fail', () async {
    for (final status in [204, 304, 404, 500]) {
      server.routes['/s$status'] = (r) async => r.statusCode = status;
      expect(await fetcher().fetch(server.url('/s$status')), isNull);
    }
  });

  test('> 16 KB with Content-Length is rejected', () async {
    server.routes['/big'] = (r) async {
      r.contentLength = maxVersionFileBytes + 1;
      r.add(List<int>.filled(maxVersionFileBytes + 1, 0x20));
    };
    expect(await fetcher().fetch(server.url('/big')), isNull);
  });

  test('> 16 KB without Content-Length (chunked) is rejected', () async {
    server.routes['/chunked'] = (r) async {
      for (var i = 0; i < 20; i++) {
        r.add(List<int>.filled(1024, 0x20));
        await r.flush();
      }
    };
    expect(await fetcher().fetch(server.url('/chunked')), isNull);
  });

  test('exactly 16 KB is accepted', () async {
    server.routes['/edge'] = (r) async =>
        r.add(List<int>.filled(maxVersionFileBytes, 0x20));
    expect(
      (await fetcher().fetch(server.url('/edge')))!.length,
      maxVersionFileBytes,
    );
  });

  test('> 16 KB after decompression is rejected', () async {
    final bomb = gzip.encode(List<int>.filled(64 * 1024, 0));
    expect(bomb.length, lessThan(1024));
    server.routes['/gzip-big'] = (r) async {
      r.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      r.contentLength = bomb.length;
      r.add(bomb);
    };
    expect(await fetcher().fetch(server.url('/gzip-big')), isNull);

    // Control: a small gzip body is decompressed and accepted.
    final small = gzip.encode(utf8.encode('{"ok":true}'));
    server.routes['/gzip-small'] = (r) async {
      r.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      r.add(small);
    };
    expect(
      utf8.decode((await fetcher().fetch(server.url('/gzip-small')))!),
      '{"ok":true}',
    );
  });

  test(
    'non-https URLs and identifying URLs are rejected before connecting',
    () async {
      final httpUrl = Uri.parse(
        'http://127.0.0.1:${server.server.port}/version.json',
      );
      for (final url in [
        httpUrl,
        Uri.parse('ftp://example.com/version.json'),
        server.url('/version.json?id=123'),
        server.url('/version.json#frag'),
        Uri.parse(
          'https://user:pw@127.0.0.1:${server.server.port}/version.json',
        ),
      ]) {
        expect(await fetcher().fetch(url), isNull, reason: '$url');
      }
      expect(factoryCalls, 0, reason: 'no client was even created');
      expect(server.requests, isEmpty);
    },
  );

  test('a slow body is cut off at the overall deadline', () async {
    final release = Completer<void>();
    server.routes['/slow'] = (r) async {
      r.contentLength = 100;
      r.add(List<int>.filled(10, 0x20));
      await r.flush();
      await release.future; // never sends the rest in time
    };
    final watch = Stopwatch()..start();
    final result = await fetcher(
      deadline: const Duration(milliseconds: 400),
    ).fetch(server.url('/slow'));
    watch.stop();
    release.complete();
    expect(result, isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('a server that never answers is cut off at the deadline', () async {
    final release = Completer<void>();
    server.routes['/hang'] = (r) => release.future;
    final watch = Stopwatch()..start();
    final result = await fetcher(
      deadline: const Duration(milliseconds: 400),
    ).fetch(server.url('/hang'));
    watch.stop();
    release.complete();
    expect(result, isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('the default deadline is 5 seconds over the whole download', () {
    expect(VersionFileFetcher().deadline, const Duration(seconds: 5));
    expect(VersionFileFetcher().maxBytes, 16 * 1024);
  });
}
