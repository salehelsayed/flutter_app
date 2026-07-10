import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
