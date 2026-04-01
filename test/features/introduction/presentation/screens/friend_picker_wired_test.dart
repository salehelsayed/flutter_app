import 'dart:async';

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

class _ControlledP2PService extends FakeP2PService {
  _ControlledP2PService({required super.peerId, required super.network});

  bool Function(String targetPeerId, String message)? blockMatcher;
  final List<Completer<void>> _blockedSendCompleters = [];
  int blockedSendCount = 0;

  @override
  Future<bool> sendMessage(String targetPeerId, String message) async {
    final shouldBlock = blockMatcher?.call(targetPeerId, message) ?? false;
    if (shouldBlock) {
      final completer = Completer<void>();
      _blockedSendCompleters.add(completer);
      blockedSendCount++;
      await completer.future;
    }

    return super.sendMessage(targetPeerId, message);
  }

  Future<void> waitForBlockedSendCount(int count) {
    return _waitForCondition(() => blockedSendCount >= count);
  }

  void releaseBlockedSendAt(int index) {
    final completer = _blockedSendCompleters[index];
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  void releaseAllBlockedSends() {
    for (var index = 0; index < _blockedSendCompleters.length; index++) {
      releaseBlockedSendAt(index);
    }
  }
}

void main() {
  testWidgets(
    'exact recipient pair exclusion keeps C visible in B picker and B visible in C picker',
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

      expect(find.text('Dana'), findsNothing);
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
    'shows truthful progress and disables send while introductions are in flight',
    (tester) async {
      final contactRepo = InMemoryContactRepository();
      final introRepo = InMemoryIntroductionRepository();
      final identityRepo = _FakeIdentityRepository(_identity());
      final network = FakeP2PNetwork();
      final p2pService = _ControlledP2PService(
        peerId: 'peer-A',
        network: network,
      );
      addTearDown(p2pService.dispose);

      final recipientB = _contact('peer-B', 'Lina');
      final friendC = _contact('peer-C', 'Sarah');
      final friendD = _contact('peer-D', 'Dana');

      contactRepo.addTestContact(recipientB);
      contactRepo.addTestContact(friendC);
      contactRepo.addTestContact(friendD);
      FakeP2PService(peerId: recipientB.peerId, network: network);
      FakeP2PService(peerId: friendC.peerId, network: network);
      FakeP2PService(peerId: friendD.peerId, network: network);

      p2pService.blockMatcher = (targetPeerId, _) => targetPeerId != 'peer-B';

      var sentCount = 0;
      await tester.pumpWidget(
        _buildSubject(
          recipient: recipientB,
          contactRepo: contactRepo,
          introRepo: introRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
          onIntroductionsSent: (introductions) {
            sentCount = introductions.length;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sarah'));
      await tester.pump();
      await tester.tap(find.text('Dana'));
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      await p2pService.waitForBlockedSendCount(2);
      await tester.pump();

      expect(find.text('Sending 0 of 2'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final sendingButton = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(sendingButton.onPressed, isNull);

      p2pService.releaseBlockedSendAt(0);
      await _pumpUntilText(tester, 'Sending 1 of 2');

      p2pService.releaseAllBlockedSends();
      await tester.pumpAndSettle();

      expect(sentCount, 2);
      expect(find.text('Sending 1 of 2'), findsNothing);
    },
  );
}

Future<void> _waitForCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for test condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _pumpUntilText(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (find.text(text).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for "$text"');
    }
    await tester.pump(const Duration(milliseconds: 10));
  }
}
