import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/screens/friend_picker_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../shared/fakes/fake_p2p_network.dart';
import '../../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../../shared/fakes/in_memory_introduction_repository.dart';

class _FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;

  _FakeIdentityRepository(this.identity);

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

class _DelayedSendFakeP2PService extends FakeP2PService {
  final Map<String, Duration> sendReplyDelayByPeerId;

  _DelayedSendFakeP2PService({
    required super.peerId,
    required super.network,
    this.sendReplyDelayByPeerId = const {},
  });

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final delay = sendReplyDelayByPeerId[targetPeerId];
    if (delay != null) {
      await Future.delayed(delay);
    }
    return super.sendMessageWithReply(
      targetPeerId,
      message,
      timeoutMs: timeoutMs,
    );
  }
}

ContactModel _contact(String peerId, String username) => ContactModel(
  peerId: peerId,
  publicKey: 'pk-$peerId',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: username,
  signature: 'sig-$peerId',
  scannedAt: '2026-03-01T10:00:00.000Z',
  mlKemPublicKey: 'mlkem-$peerId',
);

IdentityModel _identity() => IdentityModel(
  peerId: 'peer-A',
  publicKey: 'pk-peer-A',
  privateKey: 'sk-peer-A',
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  username: 'Noor',
  createdAt: '2026-03-01T09:00:00.000Z',
  updatedAt: '2026-03-01T09:00:00.000Z',
);

IntroductionModel _intro({
  required String recipientId,
  required String introducedId,
}) => IntroductionModel(
  id: 'intro-peer-A-$recipientId-$introducedId',
  introducerId: 'peer-A',
  recipientId: recipientId,
  introducedId: introducedId,
  createdAt: '2026-03-01T11:00:00.000Z',
);

Widget _buildSubject({
  required ContactModel recipient,
  required InMemoryContactRepository contactRepo,
  required InMemoryIntroductionRepository introRepo,
  required IdentityRepository identityRepo,
  required P2PService p2pService,
  ValueChanged<List<IntroductionModel>>? onIntroductionsSent,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: FriendPickerWired(
          key: ValueKey('picker-${recipient.peerId}'),
          recipient: recipient,
          contactRepo: contactRepo,
          introRepo: introRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
          identityRepo: identityRepo,
          onIntroductionsSent: onIntroductionsSent ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'INTRO-001 search select deselect and cancel create no outbox or sends',
    (tester) async {
      final contactRepo = InMemoryContactRepository();
      final introRepo = InMemoryIntroductionRepository();
      final recipient = _contact('peer-B', 'Lina');
      contactRepo.addTestContact(recipient);
      contactRepo.addTestContact(_contact('peer-C', 'Sarah'));
      contactRepo.addTestContact(_contact('peer-D', 'Dana'));
      final network = FakeP2PNetwork();
      final service = FakeP2PService(peerId: 'peer-A', network: network);
      final bridge = PassthroughCryptoBridge();
      addTearDown(service.dispose);
      var callbacks = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open picker'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SizedBox(
                    height: 500,
                    child: FriendPickerWired(
                      recipient: recipient,
                      contactRepo: contactRepo,
                      introRepo: introRepo,
                      p2pService: service,
                      bridge: bridge,
                      identityRepo: _FakeIdentityRepository(_identity()),
                      onIntroductionsSent: (_) => callbacks++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Sar');
      await tester.pump();
      expect(find.text('Dana'), findsNothing);
      await tester.tap(find.text('Sarah'));
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Sarah'));
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      // A selected friend is also safe to cancel; no submission has occurred.
      await tester.tap(find.text('Sarah'));
      await tester.pump();
      tester.testTextInput.hide();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(FriendPickerWired), findsNothing);
      expect(find.text('Open picker'), findsOneWidget);
      expect(await introRepo.getIntroductionsByIntroducer('peer-A'), isEmpty);
      expect(introRepo.allOutboxDeliveries(), isEmpty);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
      expect(bridge.sentMessages, isEmpty);
      expect(callbacks, 0);
      expect((await contactRepo.getContact('peer-B'))!.introsSentAt, isNull);
    },
  );

  testWidgets(
    'ACCESS-002 introduction controls expose labels disabled state and 44 point targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repo = InMemoryContactRepository();
      final recipient = _contact('peer-B', 'Lina');
      repo.addTestContact(recipient);
      repo.addTestContact(_contact('peer-C', 'Sarah'));
      final service = FakeP2PService(
        peerId: 'peer-A',
        network: FakeP2PNetwork(),
      );
      addTearDown(service.dispose);
      try {
        await tester.pumpWidget(
          _buildSubject(
            recipient: recipient,
            contactRepo: repo,
            introRepo: InMemoryIntroductionRepository(),
            identityRepo: _FakeIdentityRepository(_identity()),
            p2pService: service,
          ),
        );
        await tester.pumpAndSettle();
        final send = find.byType(ElevatedButton);
        expect(tester.getSize(send).height, greaterThanOrEqualTo(44));
        final disabled = tester.getSemantics(send).getSemanticsData();
        expect(disabled.label.trim(), isNotEmpty);
        expect(disabled.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
        expect(disabled.hasFlag(SemanticsFlag.isEnabled), isFalse);
        expect(disabled.hasAction(SemanticsAction.tap), isFalse);
        await tester.tap(find.text('Sarah'));
        await tester.pump();
        final enabled = tester.getSemantics(send).getSemanticsData();
        expect(enabled.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(enabled.hasFlag(SemanticsFlag.isEnabled), isTrue);
        expect(enabled.hasAction(SemanticsAction.tap), isTrue);
        final close = find.widgetWithIcon(IconButton, Icons.close);
        expect(tester.getSize(close).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final language in ['en', 'de', 'ar']) {
    testWidgets(
      'ACCESS-002 introduction Close exposes a spoken name: $language',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final repo = InMemoryContactRepository();
        final recipient = _contact('peer-B', 'Lina');
        repo.addTestContact(recipient);
        final service = FakeP2PService(
          peerId: 'peer-A',
          network: FakeP2PNetwork(),
        );
        addTearDown(service.dispose);
        try {
          await tester.pumpWidget(
            _buildSubject(
              locale: Locale(language),
              recipient: recipient,
              contactRepo: repo,
              introRepo: InMemoryIntroductionRepository(),
              identityRepo: _FakeIdentityRepository(_identity()),
              p2pService: service,
            ),
          );
          await tester.pumpAndSettle();
          final close = find.widgetWithIcon(IconButton, Icons.close);
          expect(
            tester.getSemantics(close).getSemanticsData().label.trim(),
            MaterialLocalizations.of(tester.element(close)).closeButtonTooltip,
            reason: 'Close must expose the localized spoken name',
          );
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'filters recipient, self, blocked, and archived contacts while keeping eligible friends selectable',
    (tester) async {
      final contactRepo = InMemoryContactRepository();
      final introRepo = InMemoryIntroductionRepository();
      final identityRepo = _FakeIdentityRepository(_identity());
      final p2pService = FakeP2PService(
        peerId: 'peer-A',
        network: FakeP2PNetwork(),
      );
      addTearDown(p2pService.dispose);

      final self = _contact('peer-A', 'Noor');
      final recipientB = _contact('peer-B', 'Lina');
      final blockedC = _contact('peer-C', 'Blocked');
      final archivedD = _contact('peer-D', 'Archived');
      final eligibleE = _contact('peer-E', 'Sarah');

      contactRepo.addTestContact(self);
      contactRepo.addTestContact(recipientB);
      contactRepo.addTestContact(blockedC);
      contactRepo.addTestContact(archivedD);
      contactRepo.addTestContact(eligibleE);
      await contactRepo.blockContact(blockedC.peerId);
      await contactRepo.archiveContact(archivedD.peerId);

      await tester.pumpWidget(
        _buildSubject(
          recipient: recipientB,
          contactRepo: contactRepo,
          introRepo: introRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Noor'), findsNothing);
      expect(find.text('Lina'), findsNothing);
      expect(find.text('Blocked'), findsNothing);
      expect(find.text('Archived'), findsNothing);
      expect(find.text('Sarah'), findsOneWidget);
    },
  );

  testWidgets(
    'intro history no longer hides other eligible contacts in the picker',
    (tester) async {
      final contactRepo = InMemoryContactRepository();
      final introRepo = InMemoryIntroductionRepository();
      final identityRepo = _FakeIdentityRepository(_identity());
      final p2pService = FakeP2PService(
        peerId: 'peer-A',
        network: FakeP2PNetwork(),
      );
      addTearDown(p2pService.dispose);

      final recipientB = _contact('peer-B', 'Lina');
      final friendC = _contact('peer-C', 'Sarah');
      final friendD = _contact('peer-D', 'Dana');

      contactRepo.addTestContact(recipientB);
      contactRepo.addTestContact(friendC);
      contactRepo.addTestContact(friendD);

      await introRepo.saveIntroduction(
        _intro(recipientId: recipientB.peerId, introducedId: friendD.peerId),
      );

      await tester.pumpWidget(
        _buildSubject(
          recipient: recipientB,
          contactRepo: contactRepo,
          introRepo: introRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dana'), findsOneWidget);
      expect(find.text('Sarah'), findsOneWidget);

      await tester.pumpWidget(
        _buildSubject(
          recipient: friendC,
          contactRepo: contactRepo,
          introRepo: introRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lina'), findsOneWidget);
    },
  );

  testWidgets(
    'existing same-pair intro stays selectable so the pair can be reintroduced',
    (tester) async {
      final contactRepo = InMemoryContactRepository();
      final introRepo = InMemoryIntroductionRepository();
      final identityRepo = _FakeIdentityRepository(_identity());
      final p2pService = FakeP2PService(
        peerId: 'peer-A',
        network: FakeP2PNetwork(),
      );
      addTearDown(p2pService.dispose);

      final recipientB = _contact('peer-B', 'Lina');
      final friendC = _contact('peer-C', 'Sarah');

      contactRepo.addTestContact(recipientB);
      contactRepo.addTestContact(friendC);

      await introRepo.saveIntroduction(
        _intro(recipientId: recipientB.peerId, introducedId: friendC.peerId),
      );

      await tester.pumpWidget(
        _buildSubject(
          recipient: recipientB,
          contactRepo: contactRepo,
          introRepo: introRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sarah'), findsOneWidget);

      await tester.pumpWidget(
        _buildSubject(
          recipient: friendC,
          contactRepo: contactRepo,
          introRepo: introRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lina'), findsOneWidget);
    },
  );

  testWidgets(
    'loads, searches, selects, sends with progress, and returns introductions to the parent callback',
    (tester) async {
      final network = FakeP2PNetwork();
      final recipientService = FakeP2PService(
        peerId: 'peer-B',
        network: network,
      );
      final friendCService = FakeP2PService(peerId: 'peer-C', network: network);
      final friendDService = FakeP2PService(peerId: 'peer-D', network: network);
      final contactRepo = InMemoryContactRepository();
      final introRepo = InMemoryIntroductionRepository();
      final identityRepo = _FakeIdentityRepository(_identity());
      final p2pService = _DelayedSendFakeP2PService(
        peerId: 'peer-A',
        network: network,
        sendReplyDelayByPeerId: const {'peer-D': Duration(milliseconds: 500)},
      );
      addTearDown(recipientService.dispose);
      addTearDown(friendCService.dispose);
      addTearDown(friendDService.dispose);
      addTearDown(p2pService.dispose);

      final recipientB = _contact('peer-B', 'Lina');
      final friendC = _contact('peer-C', 'Sarah');
      final friendD = _contact('peer-D', 'Dana');

      contactRepo.addTestContact(recipientB);
      contactRepo.addTestContact(friendC);
      contactRepo.addTestContact(friendD);

      List<IntroductionModel>? sentIntroductions;

      await tester.pumpWidget(
        _buildSubject(
          recipient: recipientB,
          contactRepo: contactRepo,
          introRepo: introRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
          onIntroductionsSent: (intros) => sentIntroductions = intros,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Sa');
      await tester.pump();
      expect(find.text('Sarah'), findsOneWidget);
      expect(find.text('Dana'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      await tester.tap(find.text('Sarah'));
      await tester.pump();
      await tester.tap(find.text('Dana'));
      await tester.pump();

      expect(find.text('Introduce (2)'), findsOneWidget);

      await tester.tap(find.text('Introduce (2)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Sending 1 of 2'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      expect(sentIntroductions, isNotNull);
      expect(sentIntroductions, hasLength(2));
      expect(sentIntroductions!.map((intro) => intro.introducedId).toSet(), {
        'peer-C',
        'peer-D',
      });
      expect(
        sentIntroductions!.every(
          (intro) => intro.recipientId == recipientB.peerId,
        ),
        isTrue,
      );
    },
  );
}
