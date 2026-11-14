import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Approved copy: research/bl16-video-ui-mockup-gap-v2.md and Kayan m-01fa358f.
// Key reservation: Astra replies to m-3cbc42b9 and m-501b034d.
const approvedVideoCopy = <String, Map<String, String>>{
  "en": {
    "call_video_ringing": "Ringing…",
    "call_video_waiting_for_acceptance": "Waiting for {name} to accept…",
    "call_video_action_cancel_upgrade": "Cancel request",
    "call_video_switching": "Switching to video…",
    "call_video_camera_starting": "Starting camera…",
    "call_video_waiting_for_remote": "Waiting for {name}'s video…",
    "call_video_request_declined": "Video request declined",
    "call_video_request_expired": "Video request expired",
    "call_video_request_cancelled": "Video request cancelled",
    "call_video_camera_permission_title": "Camera access is off",
    "call_video_camera_permission_body":
        "Allow camera access in Settings to turn on your video. {name} can still hear you.",
    "call_video_open_settings": "Open Settings",
    "call_video_camera_unavailable": "Camera unavailable",
    "call_video_return_caption": "Return",
    "call_row_no_answer": "No answer",
    "call_video_peer_busy": "{name} is on another call",
    "call_video_connection_lost": "Connection lost",
    "call_video_call_again": "Call again",
    "call_video_close": "Close",
    "call_video_camera_permission_body_without_audio":
        "Allow camera access in Settings to turn on your video.",
    "call_video_action_accept_upgrade": "Accept video",
    "call_video_flip_caption": "Flip",
    "call_video_camera_caption": "Camera",
    "call_video_camera_off_caption": "Camera off",
    "mic_perm_not_now": "Not now",
    "call_status_connected": "Connected",
    "call_video_status_reconnecting": "Reconnecting",
  },
  "ar": {
    "call_video_ringing": "يرن…",
    "call_video_waiting_for_acceptance": "بانتظار قبول {name}…",
    "call_video_action_cancel_upgrade": "إلغاء الطلب",
    "call_video_switching": "جارٍ التحويل إلى الفيديو…",
    "call_video_camera_starting": "جارٍ تشغيل الكاميرا…",
    "call_video_waiting_for_remote": "بانتظار فيديو {name}…",
    "call_video_request_declined": "تم رفض طلب الفيديو",
    "call_video_request_expired": "انتهت مهلة طلب الفيديو",
    "call_video_request_cancelled": "تم إلغاء طلب الفيديو",
    "call_video_camera_permission_title": "الوصول إلى الكاميرا غير مسموح",
    "call_video_camera_permission_body":
        "اسمح بالوصول إلى الكاميرا من الإعدادات لتشغيل الفيديو. صوتك ما زال مسموعًا لدى {name}.",
    "call_video_open_settings": "فتح الإعدادات",
    "call_video_camera_unavailable": "الكاميرا غير متاحة",
    "call_video_return_caption": "عودة",
    "call_row_no_answer": "لا يوجد رد",
    "call_video_peer_busy": "{name} في مكالمة أخرى",
    "call_video_connection_lost": "انقطع الاتصال",
    "call_video_call_again": "إعادة الاتصال",
    "call_video_close": "إغلاق",
    "call_video_camera_permission_body_without_audio":
        "اسمح بالوصول إلى الكاميرا من الإعدادات لتشغيل الفيديو.",
    "call_video_action_accept_upgrade": "قبول الفيديو",
    "call_video_flip_caption": "تبديل",
    "call_video_camera_caption": "الكاميرا",
    "call_video_camera_off_caption": "الكاميرا متوقفة",
    "mic_perm_not_now": "ليس الآن",
    "call_status_connected": "متصل",
    "call_video_status_reconnecting": "جارٍ إعادة الاتصال",
  },
  "de": {
    "call_video_ringing": "Klingelt …",
    "call_video_waiting_for_acceptance": "Warte auf Annahme durch {name} …",
    "call_video_action_cancel_upgrade": "Anfrage abbrechen",
    "call_video_switching": "Wechsel zu Video …",
    "call_video_camera_starting": "Kamera wird gestartet …",
    "call_video_waiting_for_remote": "Warte auf das Video von {name} …",
    "call_video_request_declined": "Videoanfrage abgelehnt",
    "call_video_request_expired": "Videoanfrage abgelaufen",
    "call_video_request_cancelled": "Videoanfrage abgebrochen",
    "call_video_camera_permission_title": "Kamerazugriff ist aus",
    "call_video_camera_permission_body":
        "Erlaube den Kamerazugriff in den Einstellungen, um dein Video einzuschalten. {name} kann dich weiterhin hören.",
    "call_video_open_settings": "Einstellungen öffnen",
    "call_video_camera_unavailable": "Kamera nicht verfügbar",
    "call_video_return_caption": "Zurück",
    "call_row_no_answer": "Keine Antwort",
    "call_video_peer_busy": "{name} ist in einem anderen Anruf",
    "call_video_connection_lost": "Verbindung verloren",
    "call_video_call_again": "Erneut anrufen",
    "call_video_close": "Schließen",
    "call_video_camera_permission_body_without_audio":
        "Erlaube den Kamerazugriff in den Einstellungen, um dein Video einzuschalten.",
    "call_video_action_accept_upgrade": "Video annehmen",
    "call_video_flip_caption": "Wechseln",
    "call_video_camera_caption": "Kamera",
    "call_video_camera_off_caption": "Kamera aus",
    "mic_perm_not_now": "Nicht jetzt",
    "call_status_connected": "Verbunden",
    "call_video_status_reconnecting": "Verbindung wird wiederhergestellt",
  },
};

Map<String, dynamic> _bundle(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Map<String, String> _generatedCopy(AppLocalizations copy, String name) => {
  'call_video_ringing': copy.call_video_ringing,
  'call_video_waiting_for_acceptance': copy.call_video_waiting_for_acceptance(
    name,
  ),
  'call_video_action_cancel_upgrade': copy.call_video_action_cancel_upgrade,
  'call_video_switching': copy.call_video_switching,
  'call_video_camera_starting': copy.call_video_camera_starting,
  'call_video_waiting_for_remote': copy.call_video_waiting_for_remote(name),
  'call_video_request_declined': copy.call_video_request_declined,
  'call_video_request_expired': copy.call_video_request_expired,
  'call_video_request_cancelled': copy.call_video_request_cancelled,
  'call_video_camera_permission_title': copy.call_video_camera_permission_title,
  'call_video_camera_permission_body': copy.call_video_camera_permission_body(
    name,
  ),
  'call_video_open_settings': copy.call_video_open_settings,
  'call_video_camera_unavailable': copy.call_video_camera_unavailable,
  'call_video_return_caption': copy.call_video_return_caption,
  'call_row_no_answer': copy.call_row_no_answer,
  'call_video_peer_busy': copy.call_video_peer_busy(name),
  'call_video_connection_lost': copy.call_video_connection_lost,
  'call_video_call_again': copy.call_video_call_again,
  'call_video_close': copy.call_video_close,
  'call_video_camera_permission_body_without_audio':
      copy.call_video_camera_permission_body_without_audio,
  'call_video_action_accept_upgrade': copy.call_video_action_accept_upgrade,
  'call_video_flip_caption': copy.call_video_flip_caption,
  'call_video_camera_caption': copy.call_video_camera_caption,
  'call_video_camera_off_caption': copy.call_video_camera_off_caption,
  'mic_perm_not_now': copy.mic_perm_not_now,
  'call_status_connected': copy.call_status_connected,
  'call_video_status_reconnecting': copy.call_video_status_reconnecting,
};

void main() {
  for (final locale in approvedVideoCopy.keys) {
    test(
      'VUI8 $locale generated API returns approved copy and interpolates name',
      () {
        final copy = lookupAppLocalizations(Locale(locale));
        // Quotes, RTL and punctuation must stay data, not become ICU syntax.
        const name = "ليلى / Ada's {camera}";
        expect(
          _generatedCopy(copy, name),
          approvedVideoCopy[locale]!.map(
            (key, value) => MapEntry(key, value.replaceAll('{name}', name)),
          ),
        );
      },
    );

    test('VUI8 $locale has every exact approved video string', () {
      final bundle = _bundle(locale);
      final expected = approvedVideoCopy[locale]!;
      // Map lookup stays nullable: a missing key is an assertion failure,
      // never a cast, missing generated getter, or loader error.
      expect({for (final key in expected.keys) key: bundle[key]}, expected);
    });

    test(
      'VUI8 $locale name placeholders and silent-audio variant are exact',
      () {
        final bundle = _bundle(locale);
        final expected = approvedVideoCopy[locale]!;
        final named = expected.keys.where(
          (key) => expected[key]!.contains('{name}'),
        );
        expect(named, isNotEmpty);
        for (final key in named) {
          expect(bundle[key], expected[key], reason: '$locale:$key missing');
          expect(
            bundle['@$key'],
            containsPair('placeholders', {
              'name': {'type': 'String'},
            }),
            reason: '$locale:$key must expose only the name parameter',
          );
        }
        const silent = 'call_video_camera_permission_body_without_audio';
        expect(bundle[silent], expected[silent]);
        expect(bundle[silent], isNot(contains('{name}')));
      },
    );

    test('VUI8 $locale retains existing captions, consent and semantics', () {
      final bundle = _bundle(locale);
      const keys = [
        'call_video_flip_caption',
        'call_video_camera_caption',
        'call_video_camera_off_caption',
        'call_video_action_accept_upgrade',
        'call_video_action_cancel_upgrade',
        'mic_perm_not_now',
      ];
      for (final key in keys) {
        expect(bundle[key], approvedVideoCopy[locale]![key]);
      }
      expect(bundle['call_video_action_switch_camera'], isNotEmpty);
      expect(bundle['call_video_action_turn_camera_off'], isNotEmpty);
      expect(
        bundle['call_video_action_switch_camera'],
        isNot(bundle['call_video_flip_caption']),
      );
      const excluded = {
        'en': 'Your camera, before they answer',
        'ar': 'كاميرتك قبل الرد',
        'de': 'Deine Kamera, bevor angenommen wird',
      };
      expect(bundle.values, isNot(contains(excluded[locale])));
    });
  }
}
