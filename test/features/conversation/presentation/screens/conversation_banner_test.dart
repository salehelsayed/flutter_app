import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/introduction/application/check_intro_banner_use_case.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_banner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/fakes/in_memory_contact_repository.dart';

Widget _buildScreen({
  bool showIntroBanner = false,
  String? bannerContactUsername,
  VoidCallback? onMakeIntroductions,
  VoidCallback? onMaybeLater,
  List<dynamic> messages = const [],
}) {
  return MaterialApp(
    home: Scaffold(
      body: ConversationScreen(
        contactPeerId: 'peer-B',
        contactUsername: 'Lina',
        connectionDate: 'March 6, 2026',
        messages: const [],
        onSend: (_) {},
        onBack: () {},
        showIntroBanner: showIntroBanner,
        bannerContactUsername: bannerContactUsername,
        onMakeIntroductions: onMakeIntroductions,
        onMaybeLater: onMaybeLater,
      ),
    ),
  );
}

void main() {
  group('ConversationScreen banner', () {
    testWidgets('banner shown when showIntroBanner is true and no messages',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        showIntroBanner: true,
        onMakeIntroductions: () {},
        onMaybeLater: () {},
      ));
      await tester.pump();

      expect(find.byType(IntroBanner), findsOneWidget);
    });

    testWidgets('banner NOT shown when showIntroBanner is false',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        showIntroBanner: false,
      ));
      await tester.pump();

      expect(find.byType(IntroBanner), findsNothing);
    });

    testWidgets('"Make introductions" callback triggers', (tester) async {
      var triggered = false;
      await tester.pumpWidget(_buildScreen(
        showIntroBanner: true,
        onMakeIntroductions: () => triggered = true,
        onMaybeLater: () {},
      ));
      await tester.pump();

      await tester.tap(find.text('Make introductions'));
      expect(triggered, isTrue);
    });

    testWidgets('"Maybe later" callback triggers', (tester) async {
      var triggered = false;
      await tester.pumpWidget(_buildScreen(
        showIntroBanner: true,
        onMakeIntroductions: () {},
        onMaybeLater: () => triggered = true,
      ));
      await tester.pump();

      await tester.tap(find.text('Maybe later'));
      expect(triggered, isTrue);
    });

    testWidgets('banner text shows contact username', (tester) async {
      await tester.pumpWidget(_buildScreen(
        showIntroBanner: true,
        bannerContactUsername: 'Lina',
        onMakeIntroductions: () {},
        onMaybeLater: () {},
      ));
      await tester.pump();

      expect(find.textContaining('Lina'), findsWidgets);
    });

    testWidgets('banner renders IntroBanner widget', (tester) async {
      await tester.pumpWidget(_buildScreen(
        showIntroBanner: true,
        onMakeIntroductions: () {},
        onMaybeLater: () {},
      ));
      await tester.pump();

      expect(find.byType(IntroBanner), findsOneWidget);
    });
  });

  group('shouldShowIntroBanner use case', () {
    late InMemoryContactRepository contactRepo;

    setUp(() {
      contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-A',
        publicKey: 'pk-A',
        rendezvous: '/rv',
        username: 'Noor',
        signature: 'sig-A',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-B',
        publicKey: 'pk-B',
        rendezvous: '/rv',
        username: 'Lina',
        signature: 'sig-B',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));
    });

    test('returns false when all contacts blocked (no eligible friends)',
        () async {
      await contactRepo.blockContact('peer-A');
      final contact = await contactRepo.getContact('peer-B');
      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact!,
        messageCount: 0,
      );
      expect(result, isFalse);
    });

    test('returns false after dismiss', () async {
      await contactRepo.dismissIntroBanner('peer-B');
      final contact = await contactRepo.getContact('peer-B');
      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact!,
        messageCount: 0,
      );
      expect(result, isFalse);
    });

    test('returns false after intros sent', () async {
      await contactRepo.setIntrosSentAt(
          'peer-B', DateTime.now().toUtc().toIso8601String());
      final contact = await contactRepo.getContact('peer-B');
      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact!,
        messageCount: 0,
      );
      expect(result, isFalse);
    });

    test('auto-dismiss: returns false after 3 messages', () async {
      final contact = await contactRepo.getContact('peer-B');
      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact!,
        messageCount: 3,
      );
      expect(result, isFalse);
    });

    test('banner state refreshes when contact is blocked', () async {
      final contact = await contactRepo.getContact('peer-B');
      // Initially should show
      final before = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact!,
        messageCount: 0,
      );
      expect(before, isTrue);

      // After blocking
      await contactRepo.blockContact('peer-B');
      final blocked = await contactRepo.getContact('peer-B');
      final after = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: blocked!,
        messageCount: 0,
      );
      expect(after, isFalse);
    });
  });
}
