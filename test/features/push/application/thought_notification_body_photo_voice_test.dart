import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const en = Locale('en');

  String body(int mediaCount) => localizedThoughtNotificationBody(
    text: '',
    mediaKind: 'image_voice',
    mediaCount: mediaCount,
    locale: en,
  );

  test('BL95 a photo and voice thought announces its photos', () {
    expect(body(2), localizedNotificationPhoto(1, locale: en));
    expect(body(4), localizedNotificationPhoto(3, locale: en));
  });

  test('BL95 a malformed photo and voice count falls back to media', () {
    final media = localizedNotificationMedia(locale: en);
    expect(body(1), media);
    expect(body(0), media);
    expect(body(-1), media);
  });
}
