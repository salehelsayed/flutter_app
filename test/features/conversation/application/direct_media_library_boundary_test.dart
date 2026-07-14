import 'dart:io';

import 'package:flutter_app/features/conversation/application/direct_media_library_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/repositories/strict_direct_media_library_repository.dart';

/// TC-233-14: the direct shared media library is a local, strictly
/// direct-scoped composition. None of its production sources may import
/// transport, bridge, relay, group/announcement implementation, download
/// machinery, or the internal forward picker.
void main() {
  test('library is local direct-scoped and transport-free', () {
    const paths = [
      'lib/features/conversation/application/direct_media_library_controller.dart',
      'lib/features/conversation/application/direct_media_library_batch_actions.dart',
      'lib/features/conversation/application/direct_media_library_batch_delete.dart',
      'lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart',
    ];
    // Comments explain boundaries; only CODE can violate them.
    String stripComments(String source) => source
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'^\s*///?.*$', multiLine: true), '');

    final sources = {
      for (final path in paths)
        path: stripComments(File(path).readAsStringSync()),
    };

    for (final entry in sources.entries) {
      for (final forbidden in const [
        // Transport / Go / relay.
        'core/bridge/',
        'core/services/p2p_service.dart',
        'go-mknoon',
        'go-relay-server',
        'P2PService',
        'storeInInbox',
        'drainOfflineInbox',
        // Sibling lanes.
        'features/groups/',
        'GroupRepository',
        'GroupMessageRepository',
        'MediaLibraryScope.group',
        'announcement',
        // Download automation (plan 229 owns retry; the library never
        // triggers an implicit transfer).
        'download_media_use_case.dart',
        'downloadMedia',
        // Internal forwarding surface (plan 232 owns Forward).
        'ShareTargetPicker',
        'share_target_picker',
      ]) {
        expect(
          entry.value,
          isNot(contains(forbidden)),
          reason: '${entry.key} must not reference $forbidden',
        );
      }
    }

    // The one library scope this surface may construct is the strict direct
    // contact scope, built internally rather than accepted from a caller.
    expect(
      sources[paths.first],
      contains('MediaLibraryScope.direct(contactPeerId)'),
    );
  });

  test(
    'bookmark race loss removes stale parent rows without sibling mutation',
    () async {
      final repo =
          StrictDirectMediaLibraryRepository(expectedContactPeerId: 'contact-1')
            ..seedPage(
              entries: [
                makeDirectLibraryEntry(
                  'att-a',
                  contactPeerId: 'contact-1',
                  messageId: 'message-private-race',
                ),
                makeDirectLibraryEntry(
                  'att-b',
                  contactPeerId: 'contact-1',
                  messageId: 'message-private-race',
                ),
                makeDirectLibraryEntry(
                  'att-neighbor',
                  contactPeerId: 'contact-1',
                  messageId: 'message-ordinary-neighbor',
                ),
              ],
            );
      final controller = DirectMediaLibraryController(
        libraryRepository: repo,
        stateRepository: repo,
        contactPeerId: 'contact-1',
      );
      await controller.loadNextPage();
      repo.directBookmarkResult = false;

      expect(await controller.toggleBookmark('att-a'), isFalse);
      expect(repo.bookmarkCalls, [(id: 'att-a', bookmarked: true)]);
      expect(repo.directBookmarkCalls, [
        (
          messageId: 'message-private-race',
          attachmentId: 'att-a',
          bookmarked: true,
        ),
      ]);
      expect(
        controller.entries.map((entry) => entry.attachment.id),
        ['att-neighbor'],
        reason: 'only stale siblings under the raced parent are reconciled',
      );
      controller.dispose();
    },
  );
}
