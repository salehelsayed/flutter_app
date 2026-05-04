/// Simulator UI smoke test for the user-reported bug:
/// when user-B taps "Accept" on a group invitation from user-A, the spinner
/// keeps spinning and the group is never joined.
///
/// Drives the actual OrbitWired widget on iOS simulator: pre-seeds a
/// PendingGroupInvite, taps the Accept button on the PendingGroupInviteCard,
/// and asserts the spinner clears and the group becomes visible within a
/// bounded deadline. Mirrors the host widget test
/// `'accepting a pending group invite from Intros joins the group'`
/// (test/features/orbit/presentation/screens/orbit_wired_test.dart) but runs
/// on IntegrationTestWidgetsFlutterBinding so it exercises the same code on
/// a real device/simulator.
///
/// If this test hangs or times out on the Accept tap, that is the
/// reproduction of the bug. Likely failure modes to investigate:
///   1. acceptPendingGroupInvite never returns (await chain hangs)
///   2. _processingPendingInviteIds is added but never removed (finally
///      block skipped because mounted is false / setState skipped)
///   3. bridge command (e.g. group:inboxRetrieveCursor) returns a shape the
///      use case loops on indefinitely
///
/// To turn this scaffold into a deterministic reproduction, comment out the
/// `bridge.responses['group:inboxRetrieveCursor'] = ...` line below — the
/// FakeBridge default `{ok: true}` lacks the `messages`/`cursor` keys the
/// use case expects, which is the closest analogue to a real-device
/// "unexpected bridge response" condition.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/secure_storage/fake_secure_key_store.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../test/features/contacts/domain/repositories/fake_contact_repository.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/in_memory_group_message_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '../test/shared/fakes/in_memory_media_attachment_repository.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';
import '../test/shared/fakes/in_memory_pending_group_invite_repository.dart';
import '../test/shared/fakes/in_memory_posts_privacy_settings_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'simulator: tapping Accept on a pending group invite clears the spinner '
    'and joins the group within 10 seconds',
    (tester) async {
      // -- arrange: full OrbitWired stack with in-memory fakes.
      final identityRepo = FakeIdentityRepository();
      final contactRepo = FakeContactRepository();
      final contactRequestRepo = FakeContactRequestRepository();
      final messageRepo = InMemoryMessageRepository();
      final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
      final postsPrivacySettingsRepo = InMemoryPostsPrivacySettingsRepository();
      addTearDown(postsPrivacySettingsRepo.dispose);

      final bridge = FakeBridge();
      final p2pService = FakeP2PService();
      final secureKeyStore = FakeSecureKeyStore();
      final mediaFileManager = FakeMediaFileManager();
      final imageProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => null,
        compressVideo: ({required path, required compress, onProgress}) async =>
            null,
      );

      // path_provider isn't useful in the integration_test harness; mock it.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'getApplicationDocumentsDirectory') {
                return '/tmp/test_docs_invite_accept_sim';
              }
              return null;
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
      });

      // Bob is the one accepting; Alice is the inviter (hard-coded into the
      // invite payload below to match the host widget test fixtures).
      final bob = IdentityModel(
        peerId: 'bob-peer-id-12345',
        publicKey: 'pk-bob',
        privateKey: 'sk-bob',
        mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
        mlKemPublicKey: 'mlkem-bob',
        username: 'Bob',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      identityRepo.seed(bob);

      // Alice is in Bob's contacts so the invite passes the sender check.
      contactRepo.seed([
        const ContactModel(
          peerId: '12D3KooWAlice',
          publicKey: 'alicePubKey64',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Alice',
          signature: 'sig-alice',
          scannedAt: '2026-04-01T00:00:00.000Z',
          mlKemPublicKey: 'aliceMlKem64',
        ),
      ]);

      final invite = _makePendingInvite(
        bob: bob,
        groupId: 'grp-sim-accept',
        groupName: 'Writers Room',
      );
      await pendingInviteRepo.savePendingInvite(invite);

      // Happy path: bridge returns an empty inbox cursor so the post-accept
      // drain finishes immediately. Comment this line out to simulate a
      // bridge that returns a shape the use case can't reconcile — that is
      // the closest fake-side analogue of the user-reported "spins forever".
      bridge.responses['group:inboxRetrieveCursor'] = {
        'ok': true,
        'messages': <Map<String, dynamic>>[],
        'cursor': '',
      };

      final crListener = ContactRequestListener(
        contactRequestStream: const Stream<ChatMessage>.empty(),
        requestRepo: contactRequestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => bob.peerId,
      );
      final cmListener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );
      final gmListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
        bridge: bridge,
      );
      final inviteListener = _SimGroupInviteListener(
        pendingInviteRepo: pendingInviteRepo,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );
      addTearDown(inviteListener.dispose);

      final orbit = OrbitWired(
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        contactRequestRepo: contactRequestRepo,
        contactRequestListener: crListener,
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        chatMessageListener: cmListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        groupRepository: groupRepo,
        groupMessageRepository: groupMsgRepo,
        groupMessageListener: gmListener,
        groupInviteListener: inviteListener,
        postsPrivacySettingsRepository: postsPrivacySettingsRepo,
        // 'intros' tab is where pending invite cards render.
        initialFilterTab: 'intros',
      );

      // Suppress noisy paint exceptions on tiny simulator surfaces.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final s = details.toString();
        if (s.contains('overflowed') ||
            s.contains('Unable to load asset') ||
            s.contains('SvgPicture')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: orbit,
        ),
      );

      // Let orbit data load and pending invite stream settle.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // -- sanity: the invite card is on screen.
      final acceptKey = ValueKey('pending-group-invite-accept-${invite.groupId}');
      final cardKey = ValueKey('pending-group-invite-${invite.groupId}');
      expect(
        find.byKey(cardKey),
        findsOneWidget,
        reason: 'invite card must be visible before tapping Accept',
      );
      expect(find.byKey(acceptKey), findsOneWidget);
      expect(find.text('Writers Room'), findsOneWidget);

      // -- act: tap Accept.
      await tester.tap(find.byKey(acceptKey));

      // -- assert: spinner must clear and the group must materialize within
      //    a bounded deadline. If the bug is reproduced, this loop will
      //    exhaust without the conditions becoming true and the test will
      //    fail with a clear "spinner never cleared" message.
      const deadline = Duration(seconds: 10);
      const tickEvery = Duration(milliseconds: 100);
      final start = DateTime.now();
      bool spinnerCleared = false;
      bool groupJoined = false;

      while (DateTime.now().difference(start) < deadline) {
        await tester.pump(tickEvery);

        // Spinner clears when the invite card is removed from the tree
        // (acceptPendingGroupInvite -> pendingInviteRepo.deletePendingInvite
        // -> _loadPendingGroupInvites repaints orbit without the card).
        spinnerCleared = find.byKey(cardKey).evaluate().isEmpty;
        groupJoined = (await groupRepo.getGroup(invite.groupId)) != null;

        if (spinnerCleared && groupJoined) break;
      }

      expect(
        spinnerCleared,
        isTrue,
        reason:
            'BUG REPRO: invite card (with spinner) is still on screen after '
            '${deadline.inSeconds}s. The Accept handler is hanging — likely '
            'inside acceptPendingGroupInvite or a bridge call it awaits.',
      );
      expect(
        groupJoined,
        isTrue,
        reason:
            'BUG REPRO: group ${invite.groupId} was never persisted after '
            '${deadline.inSeconds}s. Accept use case did not reach saveGroup.',
      );
      expect(
        await pendingInviteRepo.getPendingInvite(invite.groupId),
        isNull,
        reason: 'pending invite should be cleared after successful accept',
      );
      expect(find.text('Joined Writers Room'), findsOneWidget);
    },
  );
}

/// Builds a `PendingGroupInvite` shaped to pass auth/freshness checks for
/// `acceptPendingGroupInvite`. Lifted from `orbit_wired_test.dart::makePendingInvite`
/// — keep the two in sync if you change either.
PendingGroupInvite _makePendingInvite({
  required IdentityModel bob,
  required String groupId,
  required String groupName,
}) {
  final receivedAt = DateTime.now().toUtc();
  final createdAt = receivedAt.subtract(const Duration(hours: 6));
  final inviteTimestamp = createdAt.add(const Duration(minutes: 5));

  final groupConfig = <String, dynamic>{
    'name': groupName,
    'groupType': 'chat',
    'description': 'Invite description',
    'members': [
      {
        'peerId': '12D3KooWAlice',
        'username': 'Alice',
        'role': 'admin',
        'publicKey': 'alicePubKey64',
        'mlKemPublicKey': 'aliceMlKem64',
      },
      {
        'peerId': bob.peerId,
        'username': bob.username,
        'role': 'writer',
        'publicKey': bob.publicKey,
        'mlKemPublicKey': bob.mlKemPublicKey,
      },
    ],
    'createdBy': '12D3KooWAlice',
    'createdAt': createdAt.toIso8601String(),
  };

  final stateHash = buildGroupConfigStateHash(
    groupId: groupId,
    groupConfig: groupConfig,
  );

  final freshness = GroupInviteMembershipFreshnessProof(
    inviteId: 'invite-$groupId',
    groupId: groupId,
    recipientPeerId: bob.peerId,
    recipientDeviceId: null,
    recipientTransportPeerId: null,
    recipientMlKemPublicKey: null,
    recipientKeyPackageId: null,
    recipientKeyPackagePublicMaterial: null,
    inviterPeerId: '12D3KooWAlice',
    inviterPublicKey: 'alicePubKey64',
    keyEpoch: 1,
    groupConfigStateHash: stateHash,
    membershipWatermark: stateHash,
    issuedAt: inviteTimestamp.toUtc(),
    expiresAt: inviteTimestamp.toUtc().add(groupInviteMembershipFreshnessTtl),
    inviterMemberSnapshot: const {
      'peerId': '12D3KooWAlice',
      'username': 'Alice',
      'role': 'admin',
      'publicKey': 'alicePubKey64',
      'mlKemPublicKey': 'aliceMlKem64',
    },
  );

  final payload = GroupInvitePayload(
    id: 'invite-$groupId',
    groupId: groupId,
    groupKey: 'base64-key',
    keyEpoch: 1,
    groupConfig: groupConfig,
    senderPeerId: '12D3KooWAlice',
    senderUsername: 'Alice',
    timestamp: inviteTimestamp.toIso8601String(),
    recipientPeerId: bob.peerId,
    recipientDeviceId: null,
    recipientTransportPeerId: null,
    recipientMlKemPublicKey: null,
    recipientKeyPackageId: null,
    recipientKeyPackagePublicMaterial: null,
    welcomeKeyPackage: null,
    invitePolicy: GroupInvitePolicy(
      expiresAt: receivedAt.add(pendingGroupInviteTtl),
      allowedDevices: [bob.peerId],
      assignedRole: 'writer',
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: 1,
      welcomeKeyPackageId: null,
      welcomeKeyPackagePublicMaterialHash: null,
      welcomeKeyPackageExpiresAt: null,
    ),
    membershipFreshnessProof: freshness,
  ).withInviteSignature(signature: 'signed-invite-by-alice');

  return PendingGroupInvite.fromPayload(payload, receivedAt: receivedAt);
}

/// Minimal GroupInviteListener that exposes the repos OrbitWired's accept
/// handler reaches into, with empty incoming/joined streams. The orbit
/// accept handler reads `inviteListener.pendingInviteRepo` directly, so the
/// listener does not need to be started for this test.
class _SimGroupInviteListener extends GroupInviteListener {
  _SimGroupInviteListener({
    required super.groupRepo,
    required super.contactRepo,
    required super.bridge,
    required super.pendingInviteRepo,
  }) : super(
          groupInviteStream: const Stream<ChatMessage>.empty(),
          getOwnMlKemSecretKey: () async => null,
        );
}
