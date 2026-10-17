import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/update_store_urls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS updates use a public TestFlight HTTPS invitation', () {
    final url = updateStoreUrlFor(UpdatePlatform.ios);

    expect(url, Uri.parse('https://testflight.apple.com/join/nUVjrEYS'));
    expect(url.scheme, 'https');
    expect(url.host, 'testflight.apple.com');
    expect(url.pathSegments, ['join', isNotEmpty]);
  });

  test('Android updates keep the production Google Play page', () {
    expect(
      updateStoreUrlFor(UpdatePlatform.android),
      Uri.parse('https://play.google.com/store/apps/details?id=com.mknoon.app'),
    );
  });
}
