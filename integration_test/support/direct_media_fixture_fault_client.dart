import 'dart:convert';
import 'dart:io';

/// H2 (MEDIA-019/038) fault ops served by the disposable Plan 347 relay
/// fixture at `{probeUrl}/fault`. They act only on that run-owned relay store.
enum DirectMediaFixtureFaultOp {
  snapshot('snapshot', targeted: true),
  remove('remove', targeted: true),
  restore('restore', targeted: true),
  corrupt('corrupt', targeted: true),
  expire('expire', targeted: false),
  clockReset('clock_reset', targeted: false);

  const DirectMediaFixtureFaultOp(this.wire, {required this.targeted});

  final String wire;
  final bool targeted;
}

typedef DirectMediaFixtureTarget = ({
  String recipientPeerId,
  String attachmentId,
  String lane,
});

final class DirectMediaFixtureFaultClient {
  DirectMediaFixtureFaultClient(Uri probeUrl)
    : _faultUrl = probeUrl.replace(path: '${probeUrl.path}/fault');

  final Uri _faultUrl;

  /// Applies [op] and returns the relay's status for the target afterwards.
  Future<Map<String, Object?>> apply(
    DirectMediaFixtureFaultOp op, {
    String? recipientPeerId,
    String? attachmentId,
  }) async {
    if (op.targeted && (recipientPeerId == null || attachmentId == null)) {
      throw ArgumentError('${op.wire} needs recipientPeerId and attachmentId');
    }
    final body = <String, String>{
      'op': op.wire,
      if (op.targeted) 'recipientPeerId': recipientPeerId!,
      if (op.targeted) 'attachmentId': attachmentId!,
    };
    final response = await _send('POST', _faultUrl, jsonEncode(body));
    if (response.status != HttpStatus.ok) {
      throw StateError(
        'fault ${op.wire} refused (${response.status}): '
        '${response.body.trim()}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    return (decoded['status'] as Map?)?.cast<String, Object?>() ?? const {};
  }

  /// Lists this run's pending relay blobs, oldest first.
  Future<List<DirectMediaFixtureTarget>> pending() async {
    final response = await _send(
      'GET',
      _faultUrl.replace(queryParameters: const {'list': 'pending'}),
      null,
    );
    if (response.status != HttpStatus.ok) {
      throw StateError('pending list refused (${response.status})');
    }
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    return [
      for (final entry in (decoded['pending'] as List? ?? const []).cast<Map>())
        (
          recipientPeerId: entry['recipientPeerId'] as String,
          attachmentId: entry['attachmentId'] as String,
          lane: entry['lane'] as String? ?? '',
        ),
    ];
  }

  Future<({int status, String body})> _send(
    String method,
    Uri url,
    String? body,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(method, url);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final response = await request.close();
      return (
        status: response.statusCode,
        body: await utf8.decodeStream(response),
      );
    } finally {
      client.close(force: true);
    }
  }
}
