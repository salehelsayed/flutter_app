import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart'
    as contacts_db;
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart'
    show dbPurgeDirectContactConversationAndContact;
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/contact_profile/presentation/screens/contact_profile_screen.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/direct_contact_conversation_purge.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/swipe_action_buttons.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/swipeable_friend_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

final _owner = TestEd25519Identity.fromSeedByte(91);
final _deleted = TestEd25519Identity.fromSeedByte(92);
final _retained = TestEd25519Identity.fromSeedByte(93);
const _timestamp = '2026-10-20T10:00:00.000Z';

void main() {
  testWidgets(
    'CONTACT-007/DC-013 Orbit profile Back and Cancel preserve data; Delete purges only the consenting contact after SQL reopen',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('orbit-delete-');
        final previousPaths = PathProviderPlatform.instance;
        final previousCache = MediaFileManager.cachedDocumentsDir;
        PathProviderPlatform.instance = _DocumentsPath(root.path);
        MediaFileManager.cacheDocumentsDir(root.path);
        var fixture = await MediaRepositoryRealDbFixture.create(
          databasePath: '${root.path}/identity.db',
          databaseFactoryOverride: databaseFactoryFfiNoIsolate,
        );
        final bridge = FakeBridge();
        final p2p = FakeP2PService();
        final requests = FakeContactRequestRepository();
        final identity = FakeIdentityRepository()
          ..seed(
            FakeIdentityRepository.makeIdentity(
              peerId: _owner.peerId,
              publicKey: _owner.publicKey,
              privateKey: _owner.privateKey,
            ),
          );
        final files = MediaFileManager();
        final targetFile = File(
          '${root.path}/media/${_deleted.peerId}/target.png',
        );
        final retainedFile = File(
          '${root.path}/media/${_retained.peerId}/keep.png',
        );
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAIAAAAt/+nTAAAATklEQVR4nO3PUQkAIBTAwNfAfmY3jCH8OITBAtxm7fN1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjx2AV3NKJdv7voVAAAAAElFTkSuQmCC',
        );
        ChatMessageListener? messages;
        ContactRequestListener? contactRequests;
        try {
          await fixture.secureKeyStore.write('orbit_intro_seen_v1', '1');
          var contacts = _contacts(fixture.db);
          for (final item in [
            (
              identity: _deleted,
              name: 'Bob',
              message: 'delete-history',
              attachment: 'target',
              file: targetFile,
            ),
            (
              identity: _retained,
              name: 'Cara',
              message: 'keep-history',
              attachment: 'keep',
              file: retainedFile,
            ),
          ]) {
            await contacts.addContact(
              ContactModel(
                peerId: item.identity.peerId,
                publicKey: item.identity.publicKey,
                rendezvous: 'test-only-rendezvous',
                username: item.name,
                signature: 'test-only-signature',
                scannedAt: _timestamp,
              ),
            );
            await fixture.seedDirectParent(
              item.message,
              contactPeerId: item.identity.peerId,
            );
            await item.file.parent.create(recursive: true);
            await item.file.writeAsBytes(bytes, flush: true);
            await fixture.repo.saveAttachment(
              MediaAttachment(
                id: item.attachment,
                messageId: item.message,
                mime: 'image/png',
                size: bytes.length,
                mediaType: 'image',
                localPath: item.file.path,
                downloadStatus: 'done',
                createdAt: _timestamp,
              ),
              owner: MediaOwnerLane.direct,
            );
          }
          final retainedContact = (await contacts.getContact(
            _retained.peerId,
          ))!.toMap();
          final retainedMessage = (await fixture.messageRepo.getMessage(
            'keep-history',
          ))!.toMap();
          final retainedAttachment = await fixture.rawAttachmentRow('keep');

          Widget app() {
            messages = ChatMessageListener(
              chatMessageStream: const Stream.empty(),
              messageRepo: fixture.messageRepo,
              contactRepo: contacts,
            );
            contactRequests = ContactRequestListener(
              contactRequestStream: const Stream.empty(),
              requestRepo: requests,
              contactRepo: contacts,
              bridge: bridge,
              getOwnPeerId: () => _owner.peerId,
            );
            return MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: OrbitWired(
                initialFilterTab: 'all',
                identityRepo: identity,
                contactRepo: contacts,
                contactRequestRepo: requests,
                contactRequestListener: contactRequests!,
                messageRepo: fixture.messageRepo,
                mediaAttachmentRepo: fixture.repo,
                chatMessageListener: messages!,
                bridge: bridge,
                p2pService: p2p,
                mediaFileManager: files,
                secureKeyStore: fixture.secureKeyStore,
                imageProcessor: ImageProcessor(),
                feedClearedRepository: InMemoryFeedClearedRepository(),
              ),
            );
          }

          Future<void> expectPreserved() async {
            expect(await contacts.getContact(_deleted.peerId), isNotNull);
            expect(
              await fixture.messageRepo.getMessage('delete-history'),
              isNotNull,
            );
            expect(await fixture.rawAttachmentRow('target'), isNotNull);
            expect(await targetFile.readAsBytes(), bytes);
            expect(
              (await contacts.getContact(_retained.peerId))!.toMap(),
              retainedContact,
            );
            expect(
              (await fixture.messageRepo.getMessage('keep-history'))!.toMap(),
              retainedMessage,
            );
            expect(await fixture.rawAttachmentRow('keep'), retainedAttachment);
            expect(await retainedFile.readAsBytes(), bytes);
          }

          Finder targetRow() => find.byWidgetPredicate(
            (widget) =>
                widget is FriendRow && widget.friend.peerId == _deleted.peerId,
          );
          Finder deleteAction() => find.descendant(
            of: find.ancestor(
              of: targetRow(),
              matching: find.byType(SwipeableFriendRow),
            ),
            matching: find.byType(DeleteActionButton),
          );
          await tester.pumpWidget(app());
          await _until(tester, () => targetRow().evaluate().isNotEmpty);
          await tester.tap(
            find.descendant(of: targetRow(), matching: find.byType(UserAvatar)),
          );
          await _until(
            tester,
            () => find.byType(ContactProfileScreen).evaluate().isNotEmpty,
          );
          await _frames(tester);
          await tester.tap(find.byIcon(Icons.chevron_left_rounded));
          await _until(
            tester,
            () => find.byType(ContactProfileScreen).evaluate().isEmpty,
          );
          await expectPreserved();

          await tester.fling(targetRow(), const Offset(-350, 0), 1000);
          await _frames(tester);
          await tester.tap(deleteAction());
          await _frames(tester);
          expect(
            find.text(
              'This will permanently remove Bob, your messages and your call history with them. This cannot be undone.',
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('Cancel'));
          await _frames(tester);
          await expectPreserved();

          await tester.tap(deleteAction());
          await _frames(tester);
          final dialogDeleteAction = find.text('Delete').hitTestable();
          expect(dialogDeleteAction, findsOneWidget);
          await tester.tap(dialogDeleteAction);
          await _until(tester, () => targetRow().evaluate().isEmpty);
          expect(await contacts.getContact(_deleted.peerId), isNull);
          expect(
            await fixture.messageRepo.getMessage('delete-history'),
            isNull,
          );
          expect(await fixture.rawAttachmentRow('target'), isNull);
          expect(await targetFile.exists(), isFalse);

          await tester.pumpWidget(const SizedBox.shrink());
          messages!.dispose();
          messages = null;
          contactRequests!.dispose();
          contactRequests = null;
          fixture = await fixture.reopen();
          contacts = _contacts(fixture.db);
          expect(await contacts.getContact(_deleted.peerId), isNull);
          expect(
            await fixture.messageRepo.getMessagesForContact(_deleted.peerId),
            isEmpty,
          );
          expect(
            await fixture.repo.getAttachmentsForMessage(
              'delete-history',
              owner: MediaOwnerLane.direct,
            ),
            isEmpty,
          );
          expect(await targetFile.exists(), isFalse);
          expect(
            (await contacts.getContact(_retained.peerId))!.toMap(),
            retainedContact,
          );
          expect(
            (await fixture.messageRepo.getMessage('keep-history'))!.toMap(),
            retainedMessage,
          );
          expect(await fixture.rawAttachmentRow('keep'), retainedAttachment);
          expect(await retainedFile.readAsBytes(), bytes);
          await tester.pumpWidget(app());
          await _until(tester, () => find.text('Cara').evaluate().isNotEmpty);
          expect(find.text('Bob'), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          messages?.dispose();
          contactRequests?.dispose();
          p2p.dispose();
          bridge.dispose();
          await fixture.dispose();
          PathProviderPlatform.instance = previousPaths;
          MediaFileManager.debugResetDocumentsDirCache();
          if (previousCache != null) {
            MediaFileManager.cacheDocumentsDir(previousCache);
          }
          await root.delete(recursive: true);
        }
      });
    },
  );
}

ContactRepositoryImpl _contacts(Database db) => ContactRepositoryImpl(
  dbLoadAllContacts: () => contacts_db.dbLoadAllContacts(db),
  dbLoadContact: (id) => contacts_db.dbLoadContact(db, id),
  dbUpsertContact: (row) => contacts_db.dbUpsertContact(db, row),
  dbDeleteContact: (id) => contacts_db.dbDeleteContact(db, id),
  dbGetContactCount: () => contacts_db.dbGetContactCount(db),
  dbContactExists: (id) => contacts_db.dbContactExists(db, id),
  dbArchiveContact: (id) => contacts_db.dbArchiveContact(db, id),
  dbUnarchiveContact: (id) => contacts_db.dbUnarchiveContact(db, id),
  dbLoadActiveContacts: () => contacts_db.dbLoadActiveContacts(db),
  dbLoadArchivedContacts: () => contacts_db.dbLoadArchivedContacts(db),
  dbBlockContact: (id) => contacts_db.dbBlockContact(db, id),
  dbUnblockContact: (id) => contacts_db.dbUnblockContact(db, id),
  dbDismissIntroBanner: (id) => contacts_db.dbDismissIntroBanner(db, id),
  dbSetIntrosSentAt: (id, at) => contacts_db.dbSetIntrosSentAt(db, id, at),
  dbPurgeDirectContactConversationAndContact: (id) async {
    final result = await dbPurgeDirectContactConversationAndContact(db, id);
    return DirectContactConversationPurgeSummary(
      deletedTextCustodyRows: result.deletedTextCustodyRows,
      deletedEventCustodyRows: result.deletedEventCustodyRows,
      deletedReactions: result.deletedReactions,
      deletedMessages: result.deletedMessages,
      deletedContact: result.deletedContact,
    );
  },
);

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue, reason: 'the SQL-backed Orbit route must finish');
  await _frames(tester);
}

class _DocumentsPath extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _DocumentsPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
