import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../domain/version_file_verifier.dart';

/// Downloads the version file with strict limits. Returns null on any failure;
/// a failed download never blocks the user.
///
/// - https only, checked before any connection; no query, fragment or user
///   info in the URL.
/// - Redirects are not followed; any status other than 200 fails.
/// - ONE overall deadline over connect + headers + full body.
/// - At most [maxVersionFileBytes]: checked against Content-Length and while
///   streaming. The stream is already decompressed (`autoUncompress`), so the
///   count is of decompressed bytes.
/// - Only Dart's default headers are sent: no cookies, auth or identifiers.
/// - The client is closed in all cases.
class VersionFileFetcher {
  VersionFileFetcher({
    HttpClient Function()? clientFactory,
    this.deadline = const Duration(seconds: 5),
    this.maxBytes = maxVersionFileBytes,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  final Duration deadline;
  final int maxBytes;

  Future<Uint8List?> fetch(Uri url) async {
    if (!isAllowedVersionFileUrl(url)) return null;
    final client = _clientFactory()..autoUncompress = true;
    try {
      return await _download(client, url).timeout(deadline);
    } catch (_) {
      // Timeout, socket, TLS and HTTP failures all end here.
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List?> _download(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    request.followRedirects = false;
    final response = await request.close();
    // 3xx included: redirects count as a failed check. The forced close
    // below discards any unread body.
    if (response.statusCode != HttpStatus.ok) return null;
    if (response.contentLength > maxBytes) return null;
    final body = BytesBuilder(copy: false);
    await for (final chunk in response) {
      body.add(chunk);
      if (body.length > maxBytes) return null;
    }
    return body.takeBytes();
  }
}

/// https with a host, and nothing that could carry an identifier.
bool isAllowedVersionFileUrl(Uri url) =>
    url.scheme == 'https' &&
    url.host.isNotEmpty &&
    !url.hasQuery &&
    !url.hasFragment &&
    url.userInfo.isEmpty;
