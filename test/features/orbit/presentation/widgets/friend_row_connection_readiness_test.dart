import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  late Directory avatarDirectory;

  setUp(() {
    avatarDirectory = Directory.systemTemp.createTempSync('bl11-orbit-');
    UserAvatar.setDocumentsDir(avatarDirectory.path);
  });

  tearDown(() => avatarDirectory.deleteSync(recursive: true));

  OrbitFriend friend(String? key, {bool blocked = false}) => OrbitFriend(
    contact: ContactModel(
      peerId: 'bl11-saved-contact',
      publicKey: 'identity-key',
      rendezvous: '/dns4/relay/tcp/443',
      username: 'Alice',
      signature: 'signature',
      scannedAt: '2026-11-12T10:00:00Z',
      mlKemPublicKey: key,
      isBlocked: blocked,
    ),
    messageCount: 1,
    lastActivity: 'An existing message preview',
    unreadCount: 2,
  );

  Widget mount(OrbitFriend contact, String locale, VoidCallback onTap) =>
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FriendRow(friend: contact, onTap: onTap),
        ),
      );

  const labels = {
    'en': 'Waiting for secure connection',
    'ar': 'في انتظار اتصال آمن',
    'de': 'Warten auf eine sichere Verbindung',
  };

  for (final entry in labels.entries) {
    testWidgets('BL11 Orbit shows key readiness in ${entry.key}', (
      tester,
    ) async {
      var taps = 0;
      for (final key in <String?>[null, '', '  \n ']) {
        await tester.pumpWidget(mount(friend(key), entry.key, () => taps++));
        await tester.pump();
        expect(find.text(entry.value), findsOneWidget);
        expect(find.text('An existing message preview'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
      }

      await tester.tap(find.text('Alice'));
      expect(taps, 1);
      await tester.pumpWidget(
        mount(friend('reciprocal-key'), entry.key, () => taps++),
      );
      await tester.pump();
      expect(find.text(entry.value), findsNothing);
      expect(find.text('An existing message preview'), findsOneWidget);

      // Reconstruct the projection on reopen: no persisted acceptance claim.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(mount(friend(null), entry.key, () => taps++));
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
    });
  }

  testWidgets('BL11 ready and blocked Orbit rows do not claim to be waiting', (
    tester,
  ) async {
    for (final contact in [
      friend('reciprocal-key'),
      friend(null, blocked: true),
    ]) {
      await tester.pumpWidget(mount(contact, 'en', () {}));
      await tester.pump();
      expect(find.text(labels['en']!), findsNothing);
      expect(find.text('An existing message preview'), findsOneWidget);
    }
  });
}
