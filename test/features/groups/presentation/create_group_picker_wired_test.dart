import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/create_group_picker_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/create_group_picker_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

// --- Test fakes ---

class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;
  FakeIdentityRepository({this.identity});

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

class FakeGroupMessageListener extends GroupMessageListener {
  final Stream<GroupMessage> _externalStream;

  FakeGroupMessageListener(this._externalStream)
    : super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  @override
  Stream<GroupMessage> get groupMessageStream => _externalStream;
}

class _NoOpGroupRepo implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoOpMsgRepo implements GroupMessageRepository {
  @override
  Future<int> transitionSendingToFailed() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// --- Test data ---

final testIdentity = IdentityModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  privateKey: 'sk-admin',
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  mlKemPublicKey: 'mlkem-pk-admin',
  username: 'Admin',
  createdAt: DateTime.now().toUtc().toIso8601String(),
  updatedAt: DateTime.now().toUtc().toIso8601String(),
);

final contactAlice = ContactModel(
  peerId: 'peer-alice',
  publicKey: 'pk-alice',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Alice',
  signature: 'sig-alice',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-alice',
);

final contactBob = ContactModel(
  peerId: 'peer-bob',
  publicKey: 'pk-bob',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Bob',
  signature: 'sig-bob',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-bob',
);

// Self contact (should be excluded)
final contactSelf = ContactModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Admin',
  signature: 'sig-admin',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-admin',
);

// --- Helpers ---

Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('CreateGroupPickerWired', () {
    late InMemoryGroupRepository groupRepo;
    late InMemoryGroupMessageRepository msgRepo;
    late InMemoryContactRepository contactRepo;
    late PassthroughCryptoBridge bridge;
    late FakeIdentityRepository identityRepo;
    late FakeP2PService p2pService;
    late StreamController<GroupMessage> messageStreamController;

    setUp(() {
      groupRepo = InMemoryGroupRepository();
      msgRepo = InMemoryGroupMessageRepository();
      contactRepo = InMemoryContactRepository();
      bridge = PassthroughCryptoBridge();
      identityRepo = FakeIdentityRepository(identity: testIdentity);
      p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );
      messageStreamController = StreamController<GroupMessage>.broadcast();

      // Set up bridge response for group:create
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'new-group-id',
        'topicName': 'topic-new-group-id',
        'groupKey': 'base64-group-key',
        'keyEpoch': 0,
      };
    });

    tearDown(() {
      messageStreamController.close();
    });

    Widget buildWidget({GroupType groupType = GroupType.chat}) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CreateGroupPickerWired(
          groupType: groupType,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupMessageListener: FakeGroupMessageListener(
            messageStreamController.stream,
          ),
          contactRepo: contactRepo,
          bridge: bridge,
          identityRepo: identityRepo,
          p2pService: p2pService,
        ),
      );
    }

    testWidgets('loads and displays active contacts', (tester) async {
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactBob);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('excludes self from contact list', (tester) async {
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactSelf);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      // Alice should be visible
      expect(find.text('Alice'), findsOneWidget);
      // Admin (self) should NOT be in the picker list
      // Note: 'Admin' also appears as header text 'New Group', so we check
      // for the contact row text specifically
      expect(find.byType(CreateGroupPickerScreen), findsOneWidget);
      // Only 1 contact row (Alice), not 2
      final screen = tester.widget<CreateGroupPickerScreen>(
        find.byType(CreateGroupPickerScreen),
      );
      expect(screen.contacts.length, 1);
      expect(screen.contacts.first.peerId, 'peer-alice');
    });

    testWidgets('tapping contact toggles selection', (tester) async {
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactBob);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      // Tap Alice to select
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Panel should appear after selection
      expect(find.text('Start group chat'), findsOneWidget);

      // Verify selection state via the screen widget
      final screen1 = tester.widget<CreateGroupPickerScreen>(
        find.byType(CreateGroupPickerScreen),
      );
      expect(screen1.selectedPeerIds, contains('peer-alice'));

      // Tap Bob to also select
      await tester.tap(find.text('Bob'));
      await pumpFrames(tester);

      final screen2 = tester.widget<CreateGroupPickerScreen>(
        find.byType(CreateGroupPickerScreen),
      );
      expect(screen2.selectedPeerIds, contains('peer-alice'));
      expect(screen2.selectedPeerIds, contains('peer-bob'));
    });

    testWidgets('panel appears after selecting a contact', (tester) async {
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactBob);

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      // No panel initially
      expect(find.text('Start group chat'), findsNothing);

      // Select Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Panel should appear
      expect(find.text('Start group chat'), findsOneWidget);
    });

    testWidgets(
      'tapping Start group chat creates group and navigates to conversation',
      (tester) async {
        contactRepo.addTestContact(contactAlice);

        await tester.pumpWidget(buildWidget());
        await pumpFrames(tester);

        // Select Alice
        await tester.tap(find.text('Alice'));
        await pumpFrames(tester);

        // Tap "Start group chat"
        await tester.tap(find.text('Start group chat'));
        await pumpFrames(tester, count: 30);

        // Should navigate to GroupConversationScreen (via pushReplacement)
        expect(find.byType(GroupConversationScreen), findsOneWidget);
        // CreateGroupPickerScreen should be gone
        expect(find.byType(CreateGroupPickerScreen), findsNothing);
      },
    );

    testWidgets(
      'announcement picker route creates announcement group and sends announcement payload',
      (tester) async {
        contactRepo.addTestContact(contactAlice);

        await tester.pumpWidget(buildWidget(groupType: GroupType.announcement));
        await pumpFrames(tester);

        await tester.tap(find.text('Alice'));
        await pumpFrames(tester);

        await tester.tap(find.text('Start group chat'));
        await pumpFrames(tester, count: 30);

        final savedGroup = await groupRepo.getGroup('new-group-id');
        expect(savedGroup, isNotNull);
        expect(savedGroup!.type, GroupType.announcement);
        expect(savedGroup.myRole, GroupRole.admin);

        final createMessage = bridge.sentMessages.firstWhere(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:create',
        );
        final createPayload =
            (jsonDecode(createMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(createPayload['groupType'], 'announcement');

        expect(find.byType(GroupConversationScreen), findsOneWidget);
      },
    );

    testWidgets('shows error snackbar on failure', (tester) async {
      contactRepo.addTestContact(contactAlice);

      // Make group creation fail
      bridge.responses['group:create'] = {
        'ok': false,
        'errorCode': 'BRIDGE_ERROR',
        'errorMessage': 'Test failure',
      };

      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      // Select Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Tap "Start group chat"
      await tester.tap(find.text('Start group chat'));
      await pumpFrames(tester, count: 30);

      // Should show error snackbar
      expect(find.byType(SnackBar), findsOneWidget);
      // Should still be on picker screen
      expect(find.byType(CreateGroupPickerScreen), findsOneWidget);
    });

    testWidgets('back button pops screen', (tester) async {
      // Wrap in a navigator with a previous screen
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CreateGroupPickerWired(
                      groupType: GroupType.chat,
                      groupRepo: groupRepo,
                      msgRepo: msgRepo,
                      groupMessageListener: FakeGroupMessageListener(
                        messageStreamController.stream,
                      ),
                      contactRepo: contactRepo,
                      bridge: bridge,
                      identityRepo: identityRepo,
                      p2pService: p2pService,
                    ),
                  ),
                );
              },
              child: const Text('Open Picker'),
            ),
          ),
        ),
      );

      // Navigate to picker
      await tester.tap(find.text('Open Picker'));
      await pumpFrames(tester, count: 20);

      // Picker should be visible
      expect(find.byType(CreateGroupPickerScreen), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await pumpFrames(tester, count: 20);

      // Should be back on previous screen
      expect(find.text('Open Picker'), findsOneWidget);
      expect(find.byType(CreateGroupPickerScreen), findsNothing);
    });
  });
}
