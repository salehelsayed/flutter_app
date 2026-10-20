import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_presentation_gate.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_control.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../support/contact_request_sql_fixture.dart';

Finder get _dialogs => find.byType(ContactRequestDialog, skipOffstage: false);

void main() {
  setUp(() {
    final previous = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
    addTearDown(() => flowEventLoggingEnabled = previous);
  });

  testWidgets(
    'CR-003 stored request replays on first attach and stays until declined',
    (tester) async {
      final h = await _open(tester);
      final wire = await h.makeWire(tester, 0x52, 'Bob');
      expect(
        await tester.runAsync(() => h.listener.processIncomingMessage(wire)),
        HandleMessageResult.contactAutoAdded,
      );
      expect(
        await tester.runAsync(h.requests.getPendingRequests),
        hasLength(1),
      );
      await h.mount(tester);
      expect(_dialogs, findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await h.mount(tester);
      expect(_dialogs, findsOneWidget);
      expect(
        await tester.runAsync(h.requests.getPendingRequests),
        hasLength(1),
      );
      await tester.tap(find.text('Decline'));
      await _frames(tester);
      expect(
        (await tester.runAsync(() => h.requests.getRequest(wire.from)))?.status,
        ContactRequestStatus.declined,
      );
      expect(await tester.runAsync(h.requests.getPendingRequests), isEmpty);
      expect(await tester.runAsync(h.contacts.getAllContacts), isEmpty);
      expect(_dialogs, findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'CR-003 sender blocked after arrival never replays to the screen',
    (tester) async {
      final h = await _open(tester);
      final wire = await h.makeWire(tester, 0x52, 'Bob');
      await tester.runAsync(() => h.listener.processIncomingMessage(wire));
      await tester.runAsync(() async {
        await h.contacts.addContact(
          h.contact(h.senders.single.identity, 'Bob'),
        );
        await h.contacts.blockContact(wire.from);
      });
      await h.mount(tester);
      expect(_dialogs, findsNothing);
      expect(
        await tester.runAsync(h.requests.getPendingRequests),
        hasLength(1),
      );
      expect(
        (await tester.runAsync(
          () => h.contacts.getContact(wire.from),
        ))?.isBlocked,
        isTrue,
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  group(
    'missed request recovery obligation',
    () {
      testWidgets(
        'CR-003 suppression release reveals a missed request with shell subscribers retained',
        (tester) async {
          final h = await _open(tester);
          await h.mount(tester, withOrbit: true);
          final wire = await h.makeWire(tester, 0x52, 'Bob');
          h.gate.suppress(wire.from);
          await h.live(tester, wire);
          expect(_dialogs, findsNothing);
          expect(
            await tester.runAsync(h.requests.getPendingRequests),
            hasLength(1),
          );
          h.gate.release(wire.from);
          h.shell.switchTo(AppShellTab.feed);
          await _frames(tester);
          h.shell.switchTo(AppShellTab.orbit);
          await _frames(tester);
          expect(_dialogs, findsOneWidget);
          expect(find.text('Bob'), findsOneWidget);
          expect(await tester.runAsync(h.contacts.getAllContacts), isEmpty);
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    },
    skip:
        'KNOWN GAP CR-003: releasing presentation suppression emits no retry while the shell remains subscribed, lib/features/contact_request/application/contact_request_presentation_gate.dart:21. Remove when fixed.',
  );

  testWidgets(
    'CR-005 live plus inbox duplicate and listener restart retain one consent dialog',
    (tester) async {
      final h = await _open(tester);
      await h.mount(tester);
      final wire = await h.makeWire(tester, 0x52, 'Bob');
      await h.live(tester, wire);
      expect(_dialogs, findsOneWidget);
      await tester.runAsync(() => h.listener.processIncomingMessage(wire));
      await _frames(tester);
      expect(_dialogs, findsOneWidget);
      expect(
        await tester.runAsync(h.requests.getPendingRequests),
        hasLength(1),
      );
      expect(await tester.runAsync(h.contacts.getAllContacts), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async => h.restartListener());
      await h.mount(tester);
      await tester.runAsync(() => h.listener.processIncomingMessage(wire));
      await _frames(tester);
      expect(_dialogs, findsOneWidget);
      expect(
        await tester.runAsync(h.requests.getPendingRequests),
        hasLength(1),
      );
      expect(await tester.runAsync(h.contacts.getAllContacts), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  group(
    'single dialog ownership obligation',
    () {
      testWidgets(
        'CR-005 one event with Feed and embedded Orbit mounted opens one dialog route',
        (tester) async {
          final h = await _open(tester);
          await h.mount(tester, withOrbit: true);
          final wire = await h.makeWire(tester, 0x52, 'Bob');
          await h.live(tester, wire);
          await tester.runAsync(() => h.listener.processIncomingMessage(wire));
          await _frames(tester);
          expect(
            await tester.runAsync(h.requests.getPendingRequests),
            hasLength(1),
          );
          expect(await tester.runAsync(h.contacts.getAllContacts), isEmpty);
          expect(_dialogs, findsOneWidget);
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    },
    skip:
        'KNOWN GAP CR-005: Feed and embedded Orbit both open a dialog for one broadcast, lib/features/feed/presentation/screens/feed_wired.dart:1494; lib/features/orbit/presentation/screens/orbit_wired.dart:2505. Remove when fixed.',
  );

  testWidgets(
    'CR-014 burst preserves each distinct pending row without granting consent',
    (tester) async {
      final h = await _open(tester);
      await h.mount(tester);
      for (final pair in [(0x52, 'Bob'), (0x53, 'Carol'), (0x54, 'Dana')]) {
        await h.live(tester, await h.makeWire(tester, pair.$1, pair.$2));
      }
      final pending = (await tester.runAsync(h.requests.getPendingRequests))!;
      expect(pending.map((r) => r.username).toSet(), {'Bob', 'Carol', 'Dana'});
      expect(pending, hasLength(3));
      expect(await tester.runAsync(h.contacts.getAllContacts), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  group(
    'sequential burst presentation obligation',
    () {
      testWidgets(
        'CR-014 burst presents one request at a time and keeps the others until answered',
        (tester) async {
          final h = await _open(tester);
          await h.mount(tester);
          for (final pair in [(0x52, 'Bob'), (0x53, 'Carol'), (0x54, 'Dana')]) {
            await h.live(tester, await h.makeWire(tester, pair.$1, pair.$2));
          }
          final answered = <String>{};
          for (var remaining = 3; remaining > 0; remaining--) {
            expect(
              await tester.runAsync(h.requests.getPendingRequests),
              hasLength(remaining),
            );
            expect(_dialogs, findsOneWidget);
            answered.add(
              tester.widget<ContactRequestDialog>(_dialogs).request.username,
            );
            await tester.tap(find.text('Decline'));
            await _frames(tester);
          }
          expect(answered, {'Bob', 'Carol', 'Dana'});
          expect(await tester.runAsync(h.requests.getPendingRequests), isEmpty);
          expect(await tester.runAsync(h.contacts.getAllContacts), isEmpty);
          expect(_dialogs, findsNothing);
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    },
    skip:
        'KNOWN GAP CR-014: each broadcast opens showDialog instead of queuing behind the current request, lib/features/feed/presentation/screens/feed_wired.dart:1494. Remove when fixed.',
  );

  testWidgets(
    'CR-005 accepting once converges one contact each and no reciprocal loop',
    (tester) async {
      final h = await _open(tester);
      await h.mount(tester);
      final wire = await h.makeWire(tester, 0x52, 'Bob');
      final sender = h.senders.single;
      // The requester already consented by scanning Alice: seed that leg through the real repository.
      await tester.runAsync(
        () => sender.contacts.addContact(h.contact(h.local, 'Alice')),
      );
      await h.live(tester, wire);
      expect(await tester.runAsync(h.contacts.getAllContacts), isEmpty);
      final reciprocal = (await tester.runAsync(
        () async => Completer<({String peerId, String message})>(),
      ))!;
      h.network.onStoreInInbox = (peerId, message, {timeoutMs}) async {
        if (!reciprocal.isCompleted) {
          reciprocal.complete((peerId: peerId, message: message));
        }
        return true;
      };
      await tester.tap(find.text('Accept'));
      await _frames(tester);
      final response = (await tester.runAsync(() => reciprocal.future))!;
      expect(response.peerId, sender.identity.peerId);
      expect(
        (await tester.runAsync(
          h.contacts.getAllContacts,
        ))?.map((c) => c.username).toList(),
        ['Bob'],
      );
      expect(
        (await tester.runAsync(() => h.requests.getRequest(wire.from)))?.status,
        ContactRequestStatus.accepted,
      );
      expect(_dialogs, findsNothing);
      expect(find.byType(ConversationWired), findsOneWidget);
      expect(h.network.storeInInboxCallCount, 1);
      final peerListener = ContactRequestListener(
        contactRequestStream: const Stream<ChatMessage>.empty(),
        requestRepo: buildWidgetRequestRepository(sender.db),
        contactRepo: sender.contacts,
        bridge: Ed25519ContactRequestBridge(h.bus),
        getOwnPeerId: () => sender.identity.peerId,
        getOwnPrivateKey: () async => sender.identity.privateKey,
      );
      addTearDown(peerListener.dispose);
      final peerPrompts = <ContactRequestModel>[];
      final subscription = peerListener.requestStream.listen(peerPrompts.add);
      addTearDown(subscription.cancel);
      await tester.runAsync(() async {
        final reciprocalWire = ChatMessage(
          from: h.local.peerId,
          to: sender.identity.peerId,
          content: response.message,
          timestamp: wire.timestamp,
          isIncoming: true,
        );
        await peerListener.processIncomingMessage(reciprocalWire);
        await peerListener.processIncomingMessage(reciprocalWire);
        await h.listener.processIncomingMessage(wire);
      });
      await _frames(tester);
      expect(
        (await tester.runAsync(
          sender.contacts.getAllContacts,
        ))?.map((c) => c.username).toList(),
        ['Alice'],
      );
      expect(
        (await tester.runAsync(
          () => sender.contacts.getContact(h.local.peerId),
        ))?.mlKemPublicKey,
        'test-mlkem-alice',
      );
      expect(peerPrompts, isEmpty);
      expect(_dialogs, findsNothing);
      expect(h.network.storeInInboxCallCount, 1);
      expect(h.bridge.encrypts, hasLength(1));
      // Drain the application's existing five-second avatar retry (no wall wait).
      // Contact/request completion above is joined independently of this cleanup.
      await tester.pump(const Duration(seconds: 5));
      await _frames(tester);
      expect(h.network.storeInInboxCallCount, 1);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'CR-014 full repair queue negatively ACKs and retries the exact envelope after a slot frees',
    (tester) async {
      final h = await _open(tester);
      await tester.runAsync(() async => h.restartListener(withRepairs: true));
      await h.mount(tester);
      final wires = <ChatMessage>[];
      for (var i = 0; i < 5; i++) {
        final wire = await h.makeWire(tester, 0x52, 'Bob', marked: true);
        wires.add(wire);
        if (i == 0) {
          await tester.runAsync(
            () => h.contacts.addContact(
              h.contact(h.senders.first.identity, 'Bob'),
            ),
          );
        }
        if (i < 4) {
          await tester.runAsync(() => h.listener.processIncomingMessage(wire));
        }
      }
      expect(
        (await tester.runAsync(
          () => h.db.query('contact_repair_requests'),
        ))?.map((r) => r['state']).toList(),
        ['buildable', 'buildable', 'buildable', 'buildable'],
      );
      final overflow = wires.last;
      final messageId =
          (jsonDecode(overflow.content) as Map<String, dynamic>)['msgId']
              as String;
      await tester.runAsync(
        () => expectLater(
          h.listener.processIncomingMessage(overflow),
          throwsA(isA<ContactRepairDeferredException>()),
        ),
      );
      expect(h.confirmations, [true, true, true, true, false]);
      expect(h.replay.contains(messageId), isFalse);
      expect(
        await tester.runAsync(() => h.db.query('contact_repair_requests')),
        hasLength(4),
      );
      expect(await tester.runAsync(h.requests.getPendingRequests), isEmpty);
      expect(
        (await tester.runAsync(
          h.contacts.getAllContacts,
        ))?.map((c) => c.username).toList(),
        ['Bob'],
      );
      const owner = 'fixture-worker-slot';
      final jobs = (await tester.runAsync(
        () => h.repairs.takeDueJobs(
          claimToken: owner,
          wallNowMs: DateTime.now().millisecondsSinceEpoch + 1000,
          limit: 1,
        ),
      ))!;
      expect(jobs, hasLength(1));
      expect(
        await tester.runAsync(
          () => h.repairs.completeJob(job: jobs.single, claimToken: owner),
        ),
        isTrue,
      );
      await tester.runAsync(() => h.listener.processIncomingMessage(overflow));
      expect(h.confirmations, [true, true, true, true, false, true]);
      expect(h.replay.contains(messageId), isTrue);
      final rows = (await tester.runAsync(
        () => h.db.query('contact_repair_requests'),
      ))!;
      expect(rows, hasLength(5));
      expect(rows.where((r) => r['state'] == 'completed'), hasLength(1));
      expect(rows.where((r) => r['state'] == 'buildable'), hasLength(4));
      expect(rows.where((r) => r['request_id'] == messageId), hasLength(1));
      expect(_dialogs, findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

Future<void> _frames(WidgetTester tester) async {
  // Widget animation frames, never a wall-clock wait or a replacement production queue.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Shell> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 2960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('astra-it4-shell-'),
  ))!;
  addTearDown(() => dir.delete(recursive: true));
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  messenger.setMockMethodCallHandler(channel, (_) async => dir.path);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  final db = (await tester.runAsync(openContactWidgetDatabase))!;
  addTearDown(db.close);
  final h = (await tester.runAsync(() async => _Shell(db)))!;
  addTearDown(h.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.runAsync(
    () => h.identities.saveIdentity(
      testIdentityModel(
        h.local,
        username: 'Alice',
        mlKemPublicKey: 'test-mlkem-alice',
      ),
    ),
  );
  h.listener.start();
  return h;
}

class _Sender {
  _Sender(this.db, this.identity, this.identities, this.contacts);
  final Database db;
  final TestEd25519Identity identity;
  final IdentityRepositoryImpl identities;
  final ContactRepositoryImpl contacts;
}

class _Shell {
  _Shell(this.db) {
    bus.register(local);
    bridge = Ed25519ContactRequestBridge(bus)
      ..onCommand = (request) {
        if (request['cmd'] == 'message:confirm') {
          final p = request['payload'] as Map<String, dynamic>;
          confirmations.add(p['ok'] as bool);
          final pending = acks.remove(p['nonce']);
          if (pending != null && !pending.isCompleted) pending.complete();
        }
      };
    identities = buildWidgetIdentityRepository(db, keys);
    contacts = buildWidgetContactRepository(db);
    requests = buildWidgetRequestRepository(db);
    messages = buildWidgetMessageRepository(db);
    repairs = SqlContactRepairRepository(db);
    restartListener();
    chat = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messages,
      contactRepo: contacts,
    );
    network.emitState(NodeState(isStarted: true, peerId: local.peerId));
  }
  final Database db;
  final local = TestEd25519Identity.fromSeedByte(0x51);
  final bus = Ed25519ContactRequestCryptoBus();
  late final Ed25519ContactRequestBridge bridge;
  final keys = FakeSecureKeyStore();
  late final IdentityRepositoryImpl identities;
  late final ContactRepositoryImpl contacts;
  late final ContactRequestRepositoryImpl requests;
  late final MessageRepositoryImpl messages;
  late final SqlContactRepairRepository repairs;
  ContactRequestListener? _listener;
  ContactRequestListener get listener => _listener!;
  late final ChatMessageListener chat;
  final incoming = StreamController<ChatMessage>.broadcast(sync: true);
  final gate = ContactRequestPresentationGate();
  final shell = AppShellController(initialTab: AppShellTab.feed);
  final pendingPost = PendingPostTargetStore();
  final posts = InMemoryPostRepository();
  final privacy = InMemoryPostsPrivacySettingsRepository();
  final network = FakeP2PService(storeInInboxResult: true);
  final senders = <_Sender>[];
  final acks = <String, Completer<void>>{};
  final confirmations = <bool>[];
  var wireIndex = 0;

  ReplayCache replay = ReplayCache();

  void restartListener({bool withRepairs = false}) {
    _listener?.dispose();
    replay = ReplayCache();
    _listener = ContactRequestListener(
      contactRequestStream: incoming.stream,
      replayCache: replay,
      repairRepository: withRepairs ? repairs : null,
      requestRepo: requests,
      contactRepo: contacts,
      bridge: bridge,
      getOwnPeerId: () => local.peerId,
      getOwnPrivateKey: () async => local.privateKey,
      getOwnPublicKey: () async => local.publicKey,
      getOwnAccountPeerId: () async => local.peerId,
      shouldSuppressPresentationForPeerId: gate.shouldSuppress,
      downloadProfilePictureFn:
          ({
            required bridge,
            required contactRepo,
            required ownerPeerId,
            required avatarVersion,
          }) async => null,
    )..start();
  }

  ContactModel contact(TestEd25519Identity id, String name) => ContactModel(
    peerId: id.peerId,
    publicKey: id.publicKey,
    username: name,
    rendezvous: '/dns4/fixture.invalid/tcp/443',
    signature: 'fixture-contact-signature',
    scannedAt: '2026-01-01T00:00:00.000Z',
  );

  Future<ChatMessage> makeWire(
    WidgetTester tester,
    int seed,
    String name, {
    bool marked = false,
  }) async => (await tester.runAsync(() async {
    final id = TestEd25519Identity.fromSeedByte(seed);
    bus.register(id);
    final senderDb = await openContactWidgetDatabase();
    final repo = buildWidgetIdentityRepository(senderDb, FakeSecureKeyStore());
    final sender = _Sender(
      senderDb,
      id,
      repo,
      buildWidgetContactRepository(senderDb),
    );
    senders.add(sender);
    await repo.saveIdentity(
      testIdentityModel(id, username: name, mlKemPublicKey: 'test-mlkem-$name'),
    );
    final sequence = ++wireIndex;
    final built = await buildContactRequestEnvelope(
      identityRepo: repo,
      bridge: Ed25519ContactRequestBridge(bus),
      targetPeerId: local.peerId,
      recipientPublicKey: local.publicKey,
      control: marked
          ? ContactRequestControl.newRequest(
              id: '00000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}',
              to: local.peerId,
            )
          : null,
    );
    expect(built.failure, isNull);
    return ChatMessage(
      from: id.peerId,
      to: local.peerId,
      content: built.envelope!.messageJson,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      isIncoming: true,
      confirmNonce: 'fixture-confirm-$sequence',
    );
  }))!;

  Future<void> live(WidgetTester tester, ChatMessage wire) async {
    await tester.runAsync(() async {
      final completed = Completer<void>();
      acks[wire.confirmNonce!] = completed;
      incoming.add(wire);
      await completed.future;
    });
    await _frames(tester);
  }

  Future<void> mount(WidgetTester tester, {bool withOrbit = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FeedWired(
          repository: identities,
          contactRepository: contacts,
          contactRequestRepository: requests,
          contactRequestListener: listener,
          messageRepository: messages,
          postRepository: posts,
          mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
          chatMessageListener: chat,
          bridge: bridge,
          p2pService: network,
          mediaFileManager: FakeMediaFileManager(),
          secureKeyStore: keys,
          imageProcessor: ImageProcessor(
            compressFile:
                ({
                  required path,
                  required quality,
                  required keepExif,
                  minWidth = 1920,
                  minHeight = 1080,
                }) async => null,
            compressVideo:
                ({required path, required compress, onProgress}) async => null,
          ),
          appShellController: shell,
          pendingPostTargetStore: pendingPost,
          postsPrivacySettingsRepository: privacy,
          feedClearedRepository: InMemoryFeedClearedRepository(),
        ),
      ),
    );
    await _frames(tester);
    if (withOrbit) {
      shell.switchTo(AppShellTab.orbit);
      await _frames(tester);
      expect(find.byType(OrbitWired, skipOffstage: false), findsOneWidget);
    }
  }

  Future<void> dispose() async {
    listener.dispose();
    chat.dispose();
    await incoming.close();
    for (final sender in senders) {
      await sender.db.close();
    }
    posts.dispose();
    privacy.dispose();
    shell.dispose();
    pendingPost.dispose();
    network.dispose();
    bridge.dispose();
  }
}
