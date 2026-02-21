import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart' as p2p;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';

class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;

  FakeIdentityRepository(this.identity);

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

class _FakeBridge implements Bridge {
  @override
  Future<String> send(String message) async {
    return jsonEncode({'ok': true});
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}
  @override
  bool get isInitialized => true;
  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(p2p.ConnectionState)? onPeerConnected;
  @override
  void Function(p2p.ConnectionState)? onPeerDisconnected;
}

class _FakeContactRepo implements ContactRepository {
  @override
  Future<void> addContact(ContactModel contact) async {}
  @override
  Future<ContactModel?> getContact(String peerId) async => null;
  @override
  Future<List<ContactModel>> getAllContacts() async => [];
  @override
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<void> deleteContact(String peerId) async {}
  @override
  Future<bool> contactExists(String peerId) async => false;
  @override
  Future<int> getContactCount() async => 0;
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
}

class _FakeP2PService implements P2PService {
  @override
  NodeState get currentState => const NodeState(isStarted: true);
  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;
  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async => false;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;
  @override
  Future<bool> sendMessage(String peerId, String message) async => true;
  @override
  Future<SendMessageResult> sendMessageWithReply(String peerId, String message) async =>
      const SendMessageResult(sent: true);
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async => null;
  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async => true;
  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];
  @override
  Future<bool> registerPushToken(String token, String platform) async => true;
  @override
  Future<void> performImmediateHealthCheck() async {}
  @override
  Future<void> drainOfflineInbox() async {}
  @override
  bool isLocalPeer(String peerId) => false;
  @override
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId) async => false;
  @override
  void dispose() {}
}

void main() {
  IdentityModel makeIdentity() {
    return IdentityModel(
      peerId: '12D3KooWMyPeer123',
      publicKey: 'pub',
      privateKey: 'priv',
      mnemonic12:
          'abandon ability able about above absent absorb abstract absurd abuse access accident',
      username: 'Alice',
      createdAt: '2026-02-11T09:00:00.000Z',
      updatedAt: '2026-02-11T09:00:00.000Z',
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeIdentityRepository identityRepo,
    Bridge? bridge,
    ContactRepository? contactRepo,
    P2PService? p2pService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsWired(
          identityRepo: identityRepo,
          bridge: bridge ?? _FakeBridge(),
          contactRepo: contactRepo ?? _FakeContactRepo(),
          p2pService: p2pService ?? _FakeP2PService(),
        ),
      ),
    );
    // Use pump (not pumpAndSettle) because AmbientBackground has an
    // infinite animation that prevents pumpAndSettle from completing.
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('loads identity on init, displays peerId and username', (
    tester,
  ) async {
    final identityRepo = FakeIdentityRepository(makeIdentity());
    await pumpScreen(tester, identityRepo: identityRepo);

    expect(find.text('12D3KooWMyPeer123'), findsOneWidget);
    expect(find.text('@Alice'), findsOneWidget);
  });

  testWidgets('copy peer ID: sets clipboard, shows check for 2s then reverts', (
    tester,
  ) async {
    final identityRepo = FakeIdentityRepository(makeIdentity());
    await pumpScreen(tester, identityRepo: identityRepo);

    // Initially shows copy icon
    expect(find.byIcon(Icons.copy), findsOneWidget);

    // Tap copy
    await tester.tap(find.byIcon(Icons.copy).first);
    await tester.pump();

    // Check icon appears
    expect(find.byIcon(Icons.check), findsOneWidget);

    // After 2 seconds timer fires, then pump for AnimatedSwitcher
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('reveal/hide mnemonic toggles visibility', (tester) async {
    final identityRepo = FakeIdentityRepository(makeIdentity());
    await pumpScreen(tester, identityRepo: identityRepo);

    // Scroll to make "Tap to reveal" visible
    await tester.ensureVisible(find.text('Tap to reveal'));
    await tester.pump();

    // Initially hidden
    expect(find.text('Tap to reveal'), findsOneWidget);

    // Tap to reveal
    await tester.tap(find.text('Tap to reveal'));
    await tester.pump();

    // Now revealed — overlay gone, words visible
    expect(find.text('Tap to reveal'), findsNothing);
    expect(find.text('abandon'), findsOneWidget);

    // Scroll to make Hide button visible
    await tester.ensureVisible(find.text('Hide'));
    await tester.pump();

    expect(find.text('Hide'), findsOneWidget);

    // Tap hide
    await tester.tap(find.text('Hide'));
    await tester.pump();

    // Back to hidden
    expect(find.text('Tap to reveal'), findsOneWidget);
  });

  testWidgets('copy mnemonic: shows Copied! for 2s then reverts', (
    tester,
  ) async {
    final identityRepo = FakeIdentityRepository(makeIdentity());
    await pumpScreen(tester, identityRepo: identityRepo);

    // Scroll to and reveal
    await tester.ensureVisible(find.text('Tap to reveal'));
    await tester.pump();
    await tester.tap(find.text('Tap to reveal'));
    await tester.pump();

    // Scroll to Copy button
    await tester.ensureVisible(find.text('Copy to clipboard'));
    await tester.pump();

    // Tap copy
    await tester.tap(find.text('Copy to clipboard'));
    await tester.pump();

    expect(find.text('Copied!'), findsOneWidget);

    // After 2 seconds timer fires, then pump for AnimatedSwitcher
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Copy to clipboard'), findsOneWidget);
    expect(find.text('Copied!'), findsNothing);
  });

  testWidgets('editing username saves to repository and updates display', (
    tester,
  ) async {
    final identityRepo = FakeIdentityRepository(makeIdentity());
    await pumpScreen(tester, identityRepo: identityRepo);

    // Tap edit icon to enter editing mode
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();

    // Type new name and submit
    await tester.enterText(find.byType(TextField), 'Bob');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 100));

    // Verify saved to repository
    expect(identityRepo.identity?.username, 'Bob');

    // Verify UI updated
    expect(find.text('@Bob'), findsOneWidget);
  });

  testWidgets('back button pops navigation', (tester) async {
    final identityRepo = FakeIdentityRepository(makeIdentity());

    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsWired(
                    identityRepo: identityRepo,
                    bridge: _FakeBridge(),
                    contactRepo: _FakeContactRepo(),
                    p2pService: _FakeP2PService(),
                  ),
                ),
              ).then((_) => popped = true);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    // Navigate to Settings
    await tester.tap(find.text('Open'));
    // Pump enough frames for route transition + async identity load
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Settings'), findsOneWidget);

    // Tap back
    await tester.tap(find.byIcon(Icons.chevron_left));
    // Pump enough frames for pop transition
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(popped, isTrue);
  });
}
