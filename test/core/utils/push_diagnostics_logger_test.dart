import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/utils/push_diagnostics_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('push token summaries contain only a full hash and length', () {
    const token = 'raw-secret-token-value';
    final summary = summarizePushToken(token);
    expect(summary, 'sha256:${sha256.convert(token.codeUnits)}(length=22)');
    expect(summary, isNot(contains('raw-secret')));
    expect(summary, isNot(contains(token.substring(0, 10))));
    expect(summarizePushToken(null), '<none>');
    expect(summarizePushToken(''), '<none>');
  });
}
