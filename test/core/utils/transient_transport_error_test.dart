import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/transient_transport_error.dart';

void main() {
  for (final error in [
    'received a stateless reset',
    'connection closed (remote): code: 0x0: transport error: Application error 0x0 (remote)',
    'all 1 relays failed, last error: download incomplete: wrote 4096/4978763, err=EOF',
    'download request: read response: EOF',
    'no recent network activity',
    'context deadline exceeded',
    'all 1 relays failed, last error: download request: read response: read length: write udp4 <ip>-><ip>: sendmsg: network is unreachable',
    'all dials failed',
    'dial backoff',
    'no good addresses',
    'connection refused',
    'all 1 relays failed, last error: connection failed',
    'all 1 relays failed, last error: node not started',
    'unexpected EOF',
    'stream reset',
  ]) {
    test('retains remote custody possibility: $error', () {
      expect(
        TransientTransportError.matches(error, code: 'MEDIA_ERROR'),
        isTrue,
      );
    });
  }
  for (final error in [
    'download failed: not found',
    'download failed: not authorized',
    'DECRYPT_AUTH_ERROR',
    'content hash mismatch',
    'file exceeds max size',
    'open file: no such file or directory',
  ]) {
    test(
      'does not turn a definite nontransport result into connectivity: $error',
      () {
        expect(
          TransientTransportError.matches(error, code: 'MEDIA_ERROR'),
          isFalse,
        );
      },
    );
  }
}
