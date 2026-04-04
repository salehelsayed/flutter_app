import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/screens/friend_picker_wired.dart';
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
}) {
  return MaterialApp(
    locale: const Locale('en'),
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
}
