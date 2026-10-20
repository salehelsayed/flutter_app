import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/transient_transport_error.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';

void main() {
  for (final error in [
    'received a stateless reset',
    'connection closed (remote)',
    'no recent network activity',
    'context deadline exceeded',
    'download incomplete: wrote 4096/4978763, err=EOF',
  ]) {
    test('upload and download share connectivity classification: $error', () {
      expect(
        TransientTransportError.matches(error, code: 'MEDIA_ERROR'),
        isTrue,
      );
      final failure = classifyUploadMediaTransportFailure(
        errorCode: 'MEDIA_ERROR',
        errorMessage: error,
      );
      expect(failure.disposition, UploadMediaDisposition.connectivityRetryable);
    });
  }
}
