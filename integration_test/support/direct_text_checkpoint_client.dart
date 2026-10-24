import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Uses only the capability-bound endpoint of the existing ephemeral relay
/// fixture. IDs are hashed; payloads, keys and provider material never enter
/// this control protocol.
final class DirectTextCheckpointClient {
  DirectTextCheckpointClient(Uri probeUrl)
    : _url = probeUrl.replace(path: '${probeUrl.path}/send-checkpoint');

  final Uri _url;

  Future<Map<String, Object?>> arm(String recipientPeerId) => _request({
    'op': 'arm',
    'recipientSha256': sha256.convert(utf8.encode(recipientPeerId)).toString(),
  });

  Future<Map<String, Object?>> status() => _request(null);

  Future<Map<String, Object?>> release() => _request({'op': 'release'});

  Future<Map<String, Object?>> _request(Map<String, Object?>? command) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = command == null
          ? await client.getUrl(_url).timeout(const Duration(seconds: 5))
          : await client.postUrl(_url).timeout(const Duration(seconds: 5));
      if (command != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(command));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'owned send checkpoint unavailable (${response.statusCode})',
        );
      }
      final encoded = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 5));
      final value = Map<String, Object?>.from(jsonDecode(encoded) as Map);
      if (value['schema'] != 'mknoon.direct-text-send-checkpoint.v1') {
        throw StateError('unexpected owned checkpoint schema');
      }
      return value;
    } finally {
      client.close(force: true);
    }
  }
}
