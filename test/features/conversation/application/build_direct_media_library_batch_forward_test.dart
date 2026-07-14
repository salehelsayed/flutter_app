import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';

class _ReturningRowsRepository extends FakeMediaAttachmentRepository {
  _ReturningRowsRepository(this.rowsByMessage);

  final Map<String, List<MediaAttachment>> rowsByMessage;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => rowsByMessage[messageId] ?? const [];
}

void main() {
  late Directory tempDir;
  late Map<String, ConversationMessage> parents;
  late FakeMediaAttachmentRepository repository;
  late List<String> tokens;
  late int tokenCalls;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('direct_batch_forward_');
    parents = {};
    repository = FakeMediaAttachmentRepository();
    tokens = <String>[];
    tokenCalls = 0;
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String writeFile(String name, [List<int> bytes = const [1, 2, 3]]) {
    final file = File('${tempDir.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  ConversationMessage parent({
    required String id,
    String contactPeerId = 'contact-a',
    String text = 'caption',
    String timestamp = '2026-07-11T10:00:00.000Z',
    bool incoming = true,
    String? deletedAt,
    String? hiddenAt,
    PrivateMediaPolicy policy = const PrivateMediaPolicy.ordinary(),
    PrivateMediaLifecycleState state = PrivateMediaLifecycleState.none,
  }) => ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: incoming ? contactPeerId : 'self',
    text: text,
    timestamp: timestamp,
    status: 'delivered',
    isIncoming: incoming,
    createdAt: timestamp,
    deletedAt: deletedAt,
    hiddenAt: hiddenAt,
    privateMediaPolicy: policy,
    privateMediaState: state,
    privateMediaReceivedAtMs: policy.isPrivate ? 100 : null,
    privateMediaExpiresAtMs: policy.isPrivate ? 200 : null,
  );

  MediaAttachment row({
    required String id,
    required String messageId,
    String? path,
    String mediaType = 'image',
    String downloadStatus = 'done',
    MediaOwnerLane? owner = MediaOwnerLane.direct,
  }) => MediaAttachment(
    id: id,
    messageId: messageId,
    mime: switch (mediaType) {
      'image' => 'image/jpeg',
      'video' => 'video/mp4',
      'audio' => 'audio/mp4',
      _ => 'application/pdf',
    },
    size: 3,
    mediaType: mediaType,
    localPath: path,
    downloadStatus: downloadStatus,
    createdAt: '2026-07-11T10:00:01.000Z',
    encryptionKeyBase64: 'secret-key',
    encryptionNonce: 'secret-nonce',
    ownerLane: owner,
  );

  DirectReceivedMediaActionIdentity identity(
    String messageId,
    String attachmentId,
  ) => DirectReceivedMediaActionIdentity(
    messageId: messageId,
    attachmentId: attachmentId,
  );

  BuildDirectMediaLibraryBatchForward builder({
    FakeMediaAttachmentRepository? repositoryOverride,
    String Function()? tokenFactory,
  }) => BuildDirectMediaLibraryBatchForward(
    loadParentMessage: (messageId) async => parents[messageId],
    mediaAttachmentRepository: repositoryOverride ?? repository,
    operationTokenFactory:
        tokenFactory ??
        () {
          final token = tokens[tokenCalls];
          tokenCalls++;
          return token;
        },
    resolveStoredPath: (path) => path,
    fileExists: (path) => File(path).existsSync(),
  );

  void seed(List<({ConversationMessage parent, MediaAttachment row})> sources) {
    parents = {for (final source in sources) source.parent.id: source.parent};
    repository.seed([for (final source in sources) source.row]);
  }

  test(
    'rejects empty over-cap duplicate blank-identity and cross-scope selections before token mint',
    () async {
      final path = writeFile('valid.jpg');
      final currentParent = parent(id: 'message-1');
      final currentRow = row(
        id: 'attachment-1',
        messageId: currentParent.id,
        path: path,
      );
      seed([(parent: currentParent, row: currentRow)]);
      tokens = ['must-not-mint'];
      final subject = builder();

      Future<void> expectInvalid(
        String contactPeerId,
        List<DirectReceivedMediaActionIdentity> identities,
      ) async {
        final result = await subject.build(
          contactPeerId: contactPeerId,
          identities: identities,
        );
        expect(result.draft, isNull);
        expect(result.denial, isNotNull);
      }

      await expectInvalid('contact-a', const []);
      await expectInvalid('contact-a', [
        for (var index = 0; index < 11; index++)
          identity('m-$index', 'a-$index'),
      ]);
      await expectInvalid('contact-a', [
        identity('message-1', 'attachment-1'),
        identity('message-1', 'attachment-1'),
      ]);
      await expectInvalid('   ', [identity('message-1', 'attachment-1')]);
      await expectInvalid('contact-a', [identity(' ', 'attachment-1')]);
      await expectInvalid('contact-a', [identity('message-1', '\t')]);

      parents['message-1'] = parent(
        id: 'message-1',
        contactPeerId: 'contact-b',
      );
      final crossScope = await subject.build(
        contactPeerId: 'contact-a',
        identities: [identity('message-1', 'attachment-1')],
      );
      expect(crossScope.draft, isNull);
      expect(
        crossScope.denial,
        DirectMediaLibraryBatchForwardDenial.contactScopeMismatch,
      );
      expect(tokenCalls, 0);
    },
  );

  test(
    'qualifies every exact current direct visual source atomically',
    () async {
      final imagePath = writeFile('ordinary.jpg');
      final videoPath = writeFile('ordinary.mp4');
      final imageParent = parent(id: 'message-image');
      final videoParent = parent(id: 'message-video');
      seed([
        (
          parent: imageParent,
          row: row(
            id: 'attachment-image',
            messageId: imageParent.id,
            path: imagePath,
          ),
        ),
        (
          parent: videoParent,
          row: row(
            id: 'attachment-video',
            messageId: videoParent.id,
            path: videoPath,
            mediaType: 'video',
          ),
        ),
      ]);
      tokens = ['token-image', 'token-video'];

      final ready = await builder().build(
        contactPeerId: 'contact-a',
        identities: [
          identity('message-image', 'attachment-image'),
          identity('message-video', 'attachment-video'),
        ],
      );
      expect(ready.isReady, isTrue);
      expect(ready.draft!.items, hasLength(2));

      final scenarios =
          <({String name, ConversationMessage? parent, MediaAttachment? row})>[
            (name: 'missing parent', parent: null, row: null),
            (
              name: 'replaced parent identity',
              parent: parent(id: 'replacement'),
              row: row(
                id: 'candidate',
                messageId: 'candidate-message',
                path: imagePath,
              ),
            ),
            (
              name: 'deleted',
              parent: parent(
                id: 'candidate-message',
                deletedAt: '2026-07-11T11:00:00Z',
              ),
              row: row(
                id: 'candidate',
                messageId: 'candidate-message',
                path: imagePath,
              ),
            ),
            (
              name: 'hidden',
              parent: parent(
                id: 'candidate-message',
                hiddenAt: '2026-07-11T11:00:00Z',
              ),
              row: row(
                id: 'candidate',
                messageId: 'candidate-message',
                path: imagePath,
              ),
            ),
            (
              name: 'outgoing',
              parent: parent(id: 'candidate-message', incoming: false),
              row: row(
                id: 'candidate',
                messageId: 'candidate-message',
                path: imagePath,
              ),
            ),
            (
              name: 'private available',
              parent: parent(
                id: 'candidate-message',
                policy: const PrivateMediaPolicy.viewOnce(),
                state: PrivateMediaLifecycleState.available,
              ),
              row: row(
                id: 'candidate',
                messageId: 'candidate-message',
                path: imagePath,
              ),
            ),
            (
              name: 'private consumed',
              parent: parent(
                id: 'candidate-message',
                policy: const PrivateMediaPolicy.viewOnce(),
                state: PrivateMediaLifecycleState.consumed,
              ),
              row: row(
                id: 'candidate',
                messageId: 'candidate-message',
                path: imagePath,
              ),
            ),
            (
              name: 'unsupported policy',
              parent: parent(
                id: 'candidate-message',
                policy: const PrivateMediaPolicy.unsupported(sourceVersion: 99),
                state: PrivateMediaLifecycleState.unsupported,
              ),
              row: row(
                id: 'candidate',
                messageId: 'candidate-message',
                path: imagePath,
              ),
            ),
            for (final status in const [
              'pending',
              'failed',
              'evicted',
              'integrity_failed',
            ])
              (
                name: status,
                parent: parent(id: 'candidate-message'),
                row: row(
                  id: 'candidate',
                  messageId: 'candidate-message',
                  path: imagePath,
                  downloadStatus: status,
                ),
              ),
            (
              name: 'missing path',
              parent: parent(id: 'candidate-message'),
              row: row(id: 'candidate', messageId: 'candidate-message'),
            ),
            (
              name: 'missing bytes',
              parent: parent(id: 'candidate-message'),
              row: row(
                id: 'candidate',
                messageId: 'candidate-message',
                path: '${tempDir.path}/missing.jpg',
              ),
            ),
            for (final kind in const ['audio', 'file'])
              (
                name: kind,
                parent: parent(id: 'candidate-message'),
                row: row(
                  id: 'candidate',
                  messageId: 'candidate-message',
                  path: imagePath,
                  mediaType: kind,
                ),
              ),
            for (final owner in <MediaOwnerLane?>[MediaOwnerLane.group, null])
              (
                name: 'owner-$owner',
                parent: parent(id: 'candidate-message'),
                row: row(
                  id: 'candidate',
                  messageId: 'candidate-message',
                  path: imagePath,
                  owner: owner,
                ),
              ),
          ];

      for (final scenario in scenarios) {
        tokenCalls = 0;
        tokens = ['must-not-mint'];
        parents = {
          if (scenario.parent != null) 'candidate-message': scenario.parent!,
        };
        final looseRepo = _ReturningRowsRepository({
          if (scenario.row != null) 'candidate-message': [scenario.row!],
        });
        final result = await builder(repositoryOverride: looseRepo).build(
          contactPeerId: 'contact-a',
          identities: [identity('candidate-message', 'candidate')],
        );
        expect(result.draft, isNull, reason: scenario.name);
        expect(result.denial, isNotNull, reason: scenario.name);
        expect(tokenCalls, 0, reason: scenario.name);
      }
    },
  );

  test(
    'sorts reverse tap order and same-parent siblings by the canonical library keyset',
    () async {
      final path = writeFile('sort.jpg');
      final old = parent(
        id: 'message-z',
        timestamp: '2026-07-11T09:00:00.000Z',
      );
      final sameTimeA = parent(
        id: 'message-a',
        timestamp: '2026-07-11T10:00:00.000Z',
      );
      final sameTimeB = parent(
        id: 'message-b',
        timestamp: '2026-07-11T10:00:00.000Z',
      );
      seed([
        (
          parent: old,
          row: row(id: 'attachment-z', messageId: old.id, path: path),
        ),
        (
          parent: sameTimeA,
          row: row(id: 'attachment-a', messageId: sameTimeA.id, path: path),
        ),
        (
          parent: sameTimeB,
          row: row(id: 'attachment-a', messageId: sameTimeB.id, path: path),
        ),
        (
          parent: sameTimeB,
          row: row(id: 'attachment-b', messageId: sameTimeB.id, path: path),
        ),
      ]);
      tokens = ['token-1', 'token-2', 'token-3', 'token-4'];

      final result = await builder().build(
        contactPeerId: 'contact-a',
        identities: [
          identity(old.id, 'attachment-z'),
          identity(sameTimeA.id, 'attachment-a'),
          identity(sameTimeB.id, 'attachment-a'),
          identity(sameTimeB.id, 'attachment-b'),
        ],
      );

      expect(
        result.draft!.items.map(
          (item) => '${item.identity.messageId}/${item.identity.attachmentId}',
        ),
        [
          'message-b/attachment-b',
          'message-b/attachment-a',
          'message-a/attachment-a',
          'message-z/attachment-z',
        ],
      );
      expect(
        result.draft!.items.where(
          (item) => item.identity.messageId == 'message-b',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'creates independent captions and unique opaque tokens per attachment',
    () async {
      final path = writeFile('siblings.jpg');
      final source = parent(id: 'message-1', text: 'same caption');
      seed([
        (
          parent: source,
          row: row(id: 'attachment-a', messageId: source.id, path: path),
        ),
        (
          parent: source,
          row: row(id: 'attachment-b', messageId: source.id, path: path),
        ),
      ]);
      tokens = ['opaque-a', 'opaque-b'];

      final result = await builder().build(
        contactPeerId: 'contact-a',
        identities: [
          identity(source.id, 'attachment-a'),
          identity(source.id, 'attachment-b'),
        ],
      );
      final original = result.draft!;
      final editedItems = [
        original.items.first.copyWith(caption: ''),
        original.items.last,
      ];
      final edited = original.copyWith(items: editedItems);

      expect(original.items.map((item) => item.caption), [
        'same caption',
        'same caption',
      ]);
      expect(edited.items.map((item) => item.caption), ['', 'same caption']);
      expect(
        original.items
            .map((item) => item.forwardProvenance.operationDedupKey)
            .toSet(),
        {'opaque-a', 'opaque-b'},
      );
      expect(
        () => original.items.add(original.items.first),
        throwsUnsupportedError,
      );
      expect(source.text, 'same caption');

      tokenCalls = 0;
      final blank =
          await builder(
            tokenFactory: () {
              tokenCalls++;
              return '   ';
            },
          ).build(
            contactPeerId: 'contact-a',
            identities: [identity(source.id, 'attachment-a')],
          );
      expect(
        blank.denial,
        DirectMediaLibraryBatchForwardDenial.invalidOperationToken,
      );

      final colliding = await builder(tokenFactory: () => 'collision').build(
        contactPeerId: 'contact-a',
        identities: [
          identity(source.id, 'attachment-a'),
          identity(source.id, 'attachment-b'),
        ],
      );
      expect(
        colliding.denial,
        DirectMediaLibraryBatchForwardDenial.invalidOperationToken,
      );
      expect(colliding.draft, isNull);
    },
  );

  test(
    'dispatch revalidation preserves edited captions and tokens while refreshing paths scope kind and order',
    () async {
      final oldA = writeFile('old-a.jpg');
      final oldB = writeFile('old-b.mp4');
      final newA = writeFile('new-a.jpg');
      final newB = writeFile('new-b.mp4');
      final parentA = parent(
        id: 'message-a',
        text: 'caption-a',
        timestamp: '2026-07-11T09:00:00.000Z',
      );
      final parentB = parent(
        id: 'message-b',
        text: 'caption-b',
        timestamp: '2026-07-11T10:00:00.000Z',
      );
      seed([
        (
          parent: parentA,
          row: row(id: 'attachment-a', messageId: parentA.id, path: oldA),
        ),
        (
          parent: parentB,
          row: row(
            id: 'attachment-b',
            messageId: parentB.id,
            path: oldB,
            mediaType: 'video',
          ),
        ),
      ]);
      tokens = ['opaque-a', 'opaque-b'];
      final subject = builder();
      final initial = (await subject.build(
        contactPeerId: 'contact-a',
        identities: [
          identity(parentA.id, 'attachment-a'),
          identity(parentB.id, 'attachment-b'),
        ],
      )).draft!;
      final edited = initial.copyWith(
        items: [
          for (final item in initial.items)
            item.copyWith(
              caption: item.identity.messageId == 'message-a' ? '' : 'edited-b',
            ),
        ],
      );
      final tokensByIdentity = {
        for (final item in edited.items)
          item.identity: item.forwardProvenance.operationDedupKey,
      };

      parents = {
        'message-a': parentA.copyWith(timestamp: '2026-07-11T11:00:00.000Z'),
        'message-b': parentB,
      };
      repository.seed([
        row(id: 'attachment-a', messageId: 'message-a', path: newA),
        row(
          id: 'attachment-b',
          messageId: 'message-b',
          path: newB,
          mediaType: 'video',
        ),
      ]);

      final revalidated = await subject.revalidateForDispatch(
        contactPeerId: 'contact-a',
        draft: edited,
      );

      expect(revalidated.isReady, isTrue);
      expect(revalidated.draft!.items.map((item) => item.identity.messageId), [
        'message-a',
        'message-b',
      ]);
      expect(revalidated.draft!.items.map((item) => item.resolvedPath), [
        newA,
        newB,
      ]);
      expect(revalidated.draft!.items.map((item) => item.caption), [
        '',
        'edited-b',
      ]);
      for (final item in revalidated.draft!.items) {
        expect(
          item.forwardProvenance.operationDedupKey,
          tokensByIdentity[item.identity],
        );
      }
      expect(tokenCalls, 2, reason: 'dispatch revalidation must never remint');
    },
  );

  test(
    'one source scope kind or eligibility race denies the whole revalidation with no ready subset',
    () async {
      final path = writeFile('race.jpg');

      Future<void> runRace(String name, void Function() mutate) async {
        final parentA = parent(id: 'message-a', text: 'caption-a');
        final parentB = parent(id: 'message-b', text: 'caption-b');
        seed([
          (
            parent: parentA,
            row: row(id: 'attachment-a', messageId: parentA.id, path: path),
          ),
          (
            parent: parentB,
            row: row(id: 'attachment-b', messageId: parentB.id, path: path),
          ),
        ]);
        tokenCalls = 0;
        tokens = ['token-a', 'token-b'];
        final subject = builder();
        final initial = (await subject.build(
          contactPeerId: 'contact-a',
          identities: [
            identity('message-a', 'attachment-a'),
            identity('message-b', 'attachment-b'),
          ],
        )).draft!;
        final edited = initial.copyWith(
          items: [
            initial.items.first.copyWith(caption: 'edited'),
            initial.items.last,
          ],
        );
        mutate();

        final result = await subject.revalidateForDispatch(
          contactPeerId: 'contact-a',
          draft: edited,
        );
        expect(result.draft, isNull, reason: name);
        expect(result.denial, isNotNull, reason: name);
        expect(tokenCalls, 2, reason: '$name must not remint');
        expect(
          edited.items.first.caption,
          'edited',
          reason: '$name must not restore',
        );
      }

      await runRace('contact scope', () {
        parents['message-b'] = parent(
          id: 'message-b',
          contactPeerId: 'contact-b',
        );
      });
      await runRace('visual kind', () {
        repository.seed([
          row(id: 'attachment-a', messageId: 'message-a', path: path),
          row(
            id: 'attachment-b',
            messageId: 'message-b',
            path: path,
            mediaType: 'audio',
          ),
        ]);
      });
      await runRace('private', () {
        parents['message-b'] = parent(
          id: 'message-b',
          policy: const PrivateMediaPolicy.viewOnce(),
          state: PrivateMediaLifecycleState.available,
        );
      });
      await runRace('deleted', () {
        parents['message-b'] = parent(
          id: 'message-b',
          deletedAt: '2026-07-11T12:00:00Z',
        );
      });
      await runRace('evicted', () {
        repository.seed([
          row(id: 'attachment-a', messageId: 'message-a', path: path),
          row(
            id: 'attachment-b',
            messageId: 'message-b',
            path: path,
            downloadStatus: 'evicted',
          ),
        ]);
      });
      await runRace('replaced parent identity', () {
        parents['message-b'] = parent(id: 'replacement-message');
      });
      await runRace('wrong owner', () {
        repository.seed([
          row(id: 'attachment-a', messageId: 'message-a', path: path),
          row(
            id: 'attachment-b',
            messageId: 'message-b',
            path: path,
            owner: MediaOwnerLane.group,
          ),
        ]);
      });
      await runRace('missing path', () {
        repository.seed([
          row(id: 'attachment-a', messageId: 'message-a', path: path),
          row(id: 'attachment-b', messageId: 'message-b'),
        ]);
      });
      await runRace('missing bytes', () {
        File(path).deleteSync();
      });
    },
  );

  test(
    'draft and denial diagnostics expose no source payload or media secrets',
    () async {
      final secretPath = writeFile('secret-path.jpg');
      final source = parent(
        id: 'secret-message-id',
        contactPeerId: 'secret-contact-id',
        text: 'secret-caption-history',
      );
      seed([
        (
          parent: source,
          row: row(
            id: 'secret-attachment-id',
            messageId: source.id,
            path: secretPath,
          ),
        ),
      ]);
      tokens = ['secret-operation-token'];
      final ready = await builder().build(
        contactPeerId: source.contactPeerId,
        identities: [identity(source.id, 'secret-attachment-id')],
      );
      final denied = await builder(tokenFactory: () => '').build(
        contactPeerId: source.contactPeerId,
        identities: [identity(source.id, 'secret-attachment-id')],
      );
      final diagnostics = [
        ready.toString(),
        ready.draft.toString(),
        ready.draft!.items.single.toString(),
        denied.toString(),
        denied.denial.toString(),
      ].join('|');

      for (final secret in [
        'secret-message-id',
        'secret-contact-id',
        'secret-attachment-id',
        'secret-caption-history',
        secretPath,
        'secret-operation-token',
        'secret-key',
        'secret-nonce',
      ]) {
        expect(diagnostics, isNot(contains(secret)));
      }
      expect(denied.draft, isNull);
    },
  );
}
