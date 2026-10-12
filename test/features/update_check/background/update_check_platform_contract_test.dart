import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/features/update_check/background/update_check_notifier.dart';
import 'package:flutter_app/features/update_check/domain/update_check_notify_policy.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

// SE-41 T4a: platform contracts that host tests can read.
// AC1 iOS registration, AC6 channel and no prompt, AC8 copy and RTL.

const _kotlinPoster =
    'android/app/src/main/kotlin/com/mknoon/app/UpdateCheckNotificationPoster.kt';
const _swift = 'ios/Runner/UpdateCheckBackgroundTask.swift';

const _keys = [
  'update_notification_title_general',
  'update_notification_body_general',
  'update_notification_title_security',
  'update_notification_body_security',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('iOS registration (AC1)', () {
    test('Info.plist permits the task id; fetch mode exists', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(
        plist,
        contains(
          '<key>BGTaskSchedulerPermittedIdentifiers</key>\n'
          '\t<array>\n'
          '\t\t<string>com.mknoon.app.update-check</string>\n'
          '\t</array>',
        ),
      );
      expect(plist, contains('<string>fetch</string>'));
    });

    test('the handler is registered before launch finishes', () {
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      final register = delegate.indexOf(
        'updateCheckBackground.registerLaunchHandler()',
      );
      final superCall = delegate.indexOf(
        'let didFinish = super.application(application, didFinishLaunchingWithOptions',
      );
      expect(register, greaterThan(0));
      expect(register, lessThan(superCall));
      expect(
        File(_swift).readAsStringSync(),
        contains('"com.mknoon.app.update-check"'),
      );
    });
  });

  group('channel and permission (AC6)', () {
    test('mknoon_app_updates is its own default-importance channel', () {
      expect(mknoonAppUpdatesChannel.id, 'mknoon_app_updates');
      expect(mknoonAppUpdatesChannel.name, 'App updates');
      expect(mknoonAppUpdatesChannel.importance, Importance.defaultImportance);
      expect(mknoonNotificationChannels, contains(mknoonAppUpdatesChannel));
      final ids = mknoonNotificationChannels.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'ids are distinct');
      final kotlin = File(_kotlinPoster).readAsStringSync();
      expect(kotlin, contains('CHANNEL_ID = "mknoon_app_updates"'));
      expect(kotlin, contains('CHANNEL_NAME = "App updates"'));
      expect(kotlin, contains('IMPORTANCE_DEFAULT'));
    });

    test('no T4a code ever asks for notification permission', () {
      final sources = [
        File(_kotlinPoster).readAsStringSync(),
        File(
          'android/app/src/main/kotlin/com/mknoon/app/UpdateCheckBackgroundWork.kt',
        ).readAsStringSync(),
        File(_swift).readAsStringSync(),
        for (final file in Directory(
          'lib/features/update_check/background',
        ).listSync().whereType<File>())
          file.readAsStringSync(),
      ].join('\n');
      for (final prompt in [
        'requestAuthorization',
        'requestPermission',
        'requestNotificationsPermission',
        'requestPermissions(',
        'shouldShowRequestPermissionRationale',
      ]) {
        expect(sources, isNot(contains(prompt)), reason: prompt);
      }
    });

    test('a native "not posted" reply is a silent skip', () async {
      const channel = MethodChannel('test/update_check_notify');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      Object? reply = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (reply is PlatformException) throw reply;
        return reply;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const poster = MethodChannelUpdateNotificationPoster(channel: channel);

      expect(
        await poster.post(kind: UpdateNotifyKind.hard, title: 't', body: 'b'),
        isFalse,
      );
      expect(calls.single.arguments, {
        'kind': 'hard',
        'title': 't',
        'body': 'b',
      });
      reply = PlatformException(code: 'x');
      expect(
        await poster.post(kind: UpdateNotifyKind.soft, title: 't', body: 'b'),
        isFalse,
      );
      reply = true;
      expect(
        await poster.post(kind: UpdateNotifyKind.soft, title: 't', body: 'b'),
        isTrue,
      );
    });
  });

  group('copy (AC8)', () {
    test('EN, DE and AR have the four keys with the owner-approved copy', () {
      for (final locale in ['en', 'de', 'ar']) {
        final arb =
            jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
                as Map<String, Object?>;
        for (final key in _keys) {
          expect(arb[key], isA<String>(), reason: '$locale $key');
          expect((arb[key]! as String).trim(), isNotEmpty);
          final description =
              (arb['@$key']! as Map<String, Object?>)['description']! as String;
          expect(
            description,
            'SE-41 final copy, owner-approved 2026-10-12 (Rawi)',
            reason: '$locale $key',
          );
          expect(description, isNot(contains('TODO')));
        }
      }
    });

    test('lookup without a widget tree; unsupported locales use English', () {
      final ar = updateNotificationText(
        UpdateNotifyCopy.security,
        locale: const Locale('ar'),
      );
      expect(ar.title, 'تحديث أمني لمكنون');
      expect(ar.body, 'يتوفر تحديث أمني. اضغط للتحديث.');
      final fr = updateNotificationText(
        UpdateNotifyCopy.general,
        locale: const Locale('fr'),
      );
      expect(fr.title, lookupAppLocalizations(const Locale('en'))
          .update_notification_title_general);
    });

    testWidgets('AR renders right to left', (tester) async {
      final text = updateNotificationText(
        UpdateNotifyCopy.general,
        locale: const Locale('ar'),
      );
      late TextDirection direction;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              direction = Directionality.of(context);
              return Column(children: [Text(text.title), Text(text.body)]);
            },
          ),
        ),
      );
      expect(direction, TextDirection.rtl);
      expect(find.text('حدّث مكنون'), findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(text.body),
      );
      expect(paragraph.textDirection, TextDirection.rtl);
    });
  });
}
