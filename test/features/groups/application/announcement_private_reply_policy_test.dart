import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/announcement_private_reply_policy.dart';
import 'package:flutter_app/features/groups/application/announcement_private_reply_request.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _sourceMessageId = 'announcement-message-1';
const _groupId = 'announcement-group-1';
const _senderPeerId = 'sender-peer-1';
const _currentPeerId = 'current-peer-1';

void main() {
  test('accepted private-reply matrix is exact and fail closed', () async {
    final eligible = _Fixture();
    final result = await eligible.resolve();
    expect(result.isAvailable, isTrue);
    expect(result.contact, same(eligible.contact));
    expect(eligible.writes, isEmpty);

    final cases = <_DenialCase>[
      _DenialCase('empty source id', (f) {
        f.request = const AnnouncementPrivateReplyRequest(
          sourceMessageId: '',
          senderPeerId: _senderPeerId,
        );
      }),
      _DenialCase('source id with edge whitespace', (f) {
        const sourceId = ' $_sourceMessageId';
        f.request = const AnnouncementPrivateReplyRequest(
          sourceMessageId: sourceId,
          senderPeerId: _senderPeerId,
        );
        f.message = f.message!.copyWith(id: sourceId);
        f.attachments = <MediaAttachment>[_attachment(messageId: sourceId)];
      }),
      _DenialCase('source id with embedded control', (f) {
        const sourceId = 'announcement\u0001message';
        f.request = const AnnouncementPrivateReplyRequest(
          sourceMessageId: sourceId,
          senderPeerId: _senderPeerId,
        );
        f.message = f.message!.copyWith(id: sourceId);
        f.attachments = <MediaAttachment>[_attachment(messageId: sourceId)];
      }),
      _DenialCase('empty sender id', (f) {
        f.request = const AnnouncementPrivateReplyRequest(
          sourceMessageId: _sourceMessageId,
          senderPeerId: '',
        );
      }),
      _DenialCase('request sender with edge whitespace', (f) {
        const senderPeerId = ' $_senderPeerId';
        f.request = const AnnouncementPrivateReplyRequest(
          sourceMessageId: _sourceMessageId,
          senderPeerId: senderPeerId,
        );
        f.message = f.message!.copyWith(senderPeerId: senderPeerId);
        f.contact = _contact(peerId: senderPeerId);
      }),
      _DenialCase('request sender with embedded control', (f) {
        const senderPeerId = 'sender\u0001peer';
        f.request = const AnnouncementPrivateReplyRequest(
          sourceMessageId: _sourceMessageId,
          senderPeerId: senderPeerId,
        );
        f.message = f.message!.copyWith(senderPeerId: senderPeerId);
        f.contact = _contact(peerId: senderPeerId);
      }),
      _DenialCase('missing identity', (f) => f.identity = null),
      _DenialCase(
        'empty current peer id',
        (f) => f.identity = _identity(peerId: ''),
      ),
      _DenialCase('current identity with edge whitespace', (f) {
        const currentPeerId = ' $_currentPeerId';
        f.identity = _identity(peerId: currentPeerId);
        f.member = _member(peerId: currentPeerId);
      }),
      _DenialCase('current identity with embedded control', (f) {
        const currentPeerId = 'current\u007fpeer';
        f.identity = _identity(peerId: currentPeerId);
        f.member = _member(peerId: currentPeerId);
      }),
      _DenialCase('missing opener', (f) => f.hasCompleteOpener = false),
      _DenialCase('missing message', (f) => f.message = null),
      _DenialCase(
        'wrong returned message id',
        (f) => f.message = f.message!.copyWith(id: 'wrong-message'),
      ),
      _DenialCase(
        'sender drift',
        (f) => f.message = f.message!.copyWith(senderPeerId: 'new-sender'),
      ),
      _DenialCase(
        'empty message sender',
        (f) => f.message = f.message!.copyWith(senderPeerId: ''),
      ),
      _DenialCase(
        'outgoing message',
        (f) => f.message = f.message!.copyWith(isIncoming: false),
      ),
      _DenialCase('self-authored message', (f) {
        f.request = const AnnouncementPrivateReplyRequest(
          sourceMessageId: _sourceMessageId,
          senderPeerId: _currentPeerId,
        );
        f.message = f.message!.copyWith(senderPeerId: _currentPeerId);
        f.contact = _contact(peerId: _currentPeerId);
      }),
      _DenialCase('system row', (f) {
        f.request = const AnnouncementPrivateReplyRequest(
          sourceMessageId: 'sys-announcement-event',
          senderPeerId: _senderPeerId,
        );
        f.message = f.message!.copyWith(id: 'sys-announcement-event');
        f.attachments = <MediaAttachment>[
          _attachment(messageId: 'sys-announcement-event'),
        ];
      }),
      _DenialCase(
        'empty message group id',
        (f) => f.message = f.message!.copyWith(groupId: ''),
      ),
      _DenialCase('group id with edge whitespace', (f) {
        const groupId = ' $_groupId';
        f.message = f.message!.copyWith(groupId: groupId);
        f.group = f.group!.copyWith(id: groupId);
        f.member = _member(groupId: groupId);
      }),
      _DenialCase('group id with embedded control', (f) {
        const groupId = 'announcement\u0001group';
        f.message = f.message!.copyWith(groupId: groupId);
        f.group = f.group!.copyWith(id: groupId);
        f.member = _member(groupId: groupId);
      }),
      _DenialCase(
        'wrong returned group id',
        (f) => f.group = f.group!.copyWith(id: 'wrong-group'),
      ),
      _DenialCase(
        'deleted tombstone',
        (f) => f.deletionState = GroupMessageLocalDeletionState.deleted,
      ),
      _DenialCase(
        'unknown tombstone authority',
        (f) => f.deletionState = GroupMessageLocalDeletionState.unknown,
      ),
      _DenialCase('missing group', (f) => f.group = null),
      _DenialCase(
        'chat group',
        (f) => f.group = f.group!.copyWith(type: GroupType.chat),
      ),
      _DenialCase(
        'qa group',
        (f) => f.group = f.group!.copyWith(type: GroupType.qa),
      ),
      _DenialCase(
        'dissolved group',
        (f) => f.group = f.group!.copyWith(isDissolved: true),
      ),
      _DenialCase('missing current member', (f) => f.member = null),
      _DenialCase(
        'member has wrong group',
        (f) => f.member = _member(groupId: 'wrong-group'),
      ),
      _DenialCase(
        'member has wrong peer',
        (f) => f.member = _member(peerId: 'wrong-peer'),
      ),
      _DenialCase('no visual relationship', (f) => f.attachments = const []),
      _DenialCase(
        'direct owner collision',
        (f) => f.attachments = <MediaAttachment>[
          _attachment(ownerLane: MediaOwnerLane.direct),
        ],
      ),
      _DenialCase(
        'unresolved owner collision',
        (f) => f.attachments = <MediaAttachment>[_attachment(ownerLane: null)],
      ),
      _DenialCase(
        'wrong attachment parent',
        (f) => f.attachments = <MediaAttachment>[
          _attachment(messageId: 'wrong-message'),
        ],
      ),
      _DenialCase(
        'audio is not visual',
        (f) => f.attachments = <MediaAttachment>[
          _attachment(mediaType: 'audio', mime: 'audio/ogg'),
        ],
      ),
      _DenialCase(
        'file is not visual',
        (f) => f.attachments = <MediaAttachment>[
          _attachment(mediaType: 'file', mime: 'application/pdf'),
        ],
      ),
      _DenialCase('missing contact', (f) => f.contact = null),
      _DenialCase(
        'mismatched contact peer',
        (f) => f.contact = _contact(peerId: 'wrong-peer'),
      ),
      _DenialCase(
        'archived contact',
        (f) => f.contact = f.contact!.copyWith(isArchived: true),
      ),
      _DenialCase(
        'blocked contact',
        (f) => f.contact = f.contact!.copyWith(isBlocked: true),
      ),
    ];

    for (final denial in cases) {
      final fixture = _Fixture();
      denial.mutate(fixture);
      final denied = await fixture.resolve();
      expect(
        denied,
        same(AnnouncementPrivateReplyResolution.unavailable),
        reason: denial.name,
      );
      expect(denied.isAvailable, isFalse, reason: denial.name);
      expect(denied.contact, isNull, reason: denial.name);
      expect(fixture.writes, isEmpty, reason: denial.name);
    }

    final archivedGroup = _Fixture()
      ..group = _Fixture().group!.copyWith(isArchived: true);
    expect((await archivedGroup.resolve()).isAvailable, isTrue);
  });

  test(
    'resolver re-reads every authority and returns one privacy-minimized result',
    () async {
      final fixture = _Fixture();
      expect((await fixture.resolve()).isAvailable, isTrue);
      expect(fixture.reads, <String, int>{
        'identity': 1,
        'message': 1,
        'deletion': 1,
        'group': 1,
        'member': 1,
        'attachments': 1,
        'contact': 1,
      });
      expect(fixture.requestedAttachmentOwners, <MediaOwnerLane>[
        MediaOwnerLane.group,
      ]);

      final mutations = <String, void Function(_Fixture)>{
        'sender drift': (f) =>
            f.message = f.message!.copyWith(senderPeerId: 'changed-sender'),
        'membership removal': (f) => f.member = null,
        'new tombstone': (f) =>
            f.deletionState = GroupMessageLocalDeletionState.deleted,
        'contact block': (f) =>
            f.contact = f.contact!.copyWith(isBlocked: true),
        'group dissolution': (f) =>
            f.group = f.group!.copyWith(isDissolved: true),
      };
      for (final mutation in mutations.entries) {
        final mutable = _Fixture();
        expect((await mutable.resolve()).isAvailable, isTrue);
        mutation.value(mutable);
        expect(
          await mutable.resolve(),
          same(AnnouncementPrivateReplyResolution.unavailable),
          reason: mutation.key,
        );
        expect(mutable.reads['identity'], 2, reason: mutation.key);
        expect(mutable.reads['message'], 2, reason: mutation.key);
        expect(mutable.writes, isEmpty, reason: mutation.key);
      }

      final openerLoss = _Fixture();
      expect((await openerLoss.resolve()).isAvailable, isTrue);
      openerLoss.hasCompleteOpener = false;
      expect(
        await openerLoss.resolve(),
        same(AnnouncementPrivateReplyResolution.unavailable),
      );
      expect(openerLoss.reads['identity'], 1);
      expect(openerLoss.writes, isEmpty);

      final sameUnavailable = <AnnouncementPrivateReplyResolution>[];
      for (final mutate in <void Function(_Fixture)>[
        (f) => f.message = null,
        (f) => f.member = null,
        (f) => f.contact = f.contact!.copyWith(isBlocked: true),
      ]) {
        final denied = _Fixture();
        mutate(denied);
        sameUnavailable.add(await denied.resolve());
      }
      expect(
        sameUnavailable,
        everyElement(same(AnnouncementPrivateReplyResolution.unavailable)),
      );
    },
  );

  test(
    'unknown tombstone authority and repository errors deny without side effects',
    () async {
      final unknown = _Fixture(useDeletionCapability: false);
      expect(
        await unknown.resolve(),
        same(AnnouncementPrivateReplyResolution.unavailable),
      );
      expect(unknown.writes, isEmpty);

      for (final seam in <String>[
        'identity',
        'message',
        'deletion',
        'group',
        'member',
        'attachments',
        'contact',
      ]) {
        final fixture = _Fixture()..throwingSeams.add(seam);
        expect(
          await fixture.resolve(),
          same(AnnouncementPrivateReplyResolution.unavailable),
          reason: seam,
        );
        expect(fixture.writes, isEmpty, reason: seam);
      }

      final absentLoader = _realMessageRepository();
      expect(
        await absentLoader.getGroupMessageLocalDeletionState(_sourceMessageId),
        GroupMessageLocalDeletionState.unknown,
      );

      final clearLoader = _realMessageRepository(
        deletionLoader: (_) async => null,
      );
      expect(
        await clearLoader.getGroupMessageLocalDeletionState(_sourceMessageId),
        GroupMessageLocalDeletionState.knownClear,
      );

      final otherGroupTombstone = _realMessageRepository(
        deletionLoader: (_) async => <String, Object?>{
          'message_id': _sourceMessageId,
          'group_id': 'entirely-different-group',
        },
      );
      expect(
        await otherGroupTombstone.getGroupMessageLocalDeletionState(
          _sourceMessageId,
        ),
        GroupMessageLocalDeletionState.deleted,
      );
    },
  );

  test(
    'visual relationship does not require a downloaded local copy',
    () async {
      for (final variant
          in <({String mediaType, String mime, String status, String? path})>[
            (
              mediaType: 'image',
              mime: 'image/jpeg',
              status: 'pending',
              path: null,
            ),
            (
              mediaType: 'image',
              mime: 'image/png',
              status: 'failed',
              path: null,
            ),
            (
              mediaType: 'video',
              mime: 'video/mp4',
              status: 'pending',
              path: null,
            ),
            (
              mediaType: 'video',
              mime: 'video/webm',
              status: 'failed',
              path: null,
            ),
          ]) {
        final fixture = _Fixture()
          ..attachments = <MediaAttachment>[
            _attachment(
              mediaType: variant.mediaType,
              mime: variant.mime,
              downloadStatus: variant.status,
              localPath: variant.path,
            ),
          ];
        final result = await fixture.resolve();
        expect(result.isAvailable, isTrue, reason: '$variant');
        expect(fixture.writes, isEmpty, reason: '$variant');
      }
    },
  );
}

class _DenialCase {
  const _DenialCase(this.name, this.mutate);

  final String name;
  final void Function(_Fixture fixture) mutate;
}

class _Fixture {
  _Fixture({this.useDeletionCapability = true});

  final bool useDeletionCapability;
  AnnouncementPrivateReplyRequest request =
      const AnnouncementPrivateReplyRequest(
        sourceMessageId: _sourceMessageId,
        senderPeerId: _senderPeerId,
      );
  bool hasCompleteOpener = true;
  IdentityModel? identity = _identity();
  GroupMessage? message = _message();
  GroupMessageLocalDeletionState deletionState =
      GroupMessageLocalDeletionState.knownClear;
  GroupModel? group = _group();
  GroupMember? member = _member();
  List<MediaAttachment> attachments = <MediaAttachment>[_attachment()];
  ContactModel? contact = _contact();
  final Set<String> throwingSeams = <String>{};
  final Map<String, int> reads = <String, int>{};
  final List<String> writes = <String>[];
  final List<MediaOwnerLane> requestedAttachmentOwners = <MediaOwnerLane>[];

  Future<AnnouncementPrivateReplyResolution> resolve() {
    final groupMessageRepository = useDeletionCapability
        ? _CapableMessageRepository(this)
        : _NonCapableMessageRepository(this);
    return AnnouncementPrivateReplyResolver(
      identityRepository: _IdentityRepository(this),
      groupMessageRepository: groupMessageRepository,
      groupRepository: _GroupRepository(this),
      mediaAttachmentRepository: _MediaRepository(this),
      contactRepository: _ContactRepository(this),
    ).resolve(request, hasCompleteOpener: hasCompleteOpener);
  }

  void recordRead(String seam) {
    reads[seam] = (reads[seam] ?? 0) + 1;
    if (throwingSeams.contains(seam)) {
      throw StateError('$seam unavailable');
    }
  }
}

class _IdentityRepository implements IdentityRepository {
  _IdentityRepository(this.fixture);

  final _Fixture fixture;

  @override
  Future<IdentityModel?> loadIdentity() async {
    fixture.recordRead('identity');
    return fixture.identity;
  }

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    fixture.writes.add('identity.save');
  }
}

class _CapableMessageRepository extends _NonCapableMessageRepository
    implements GroupMessageLocalDeletionAuthority {
  _CapableMessageRepository(super.fixture);

  @override
  Future<GroupMessageLocalDeletionState> getGroupMessageLocalDeletionState(
    String messageId,
  ) async {
    fixture.recordRead('deletion');
    return fixture.deletionState;
  }
}

class _NonCapableMessageRepository implements GroupMessageRepository {
  _NonCapableMessageRepository(this.fixture);

  final _Fixture fixture;

  @override
  Future<GroupMessage?> getMessage(String id) async {
    fixture.recordRead('message');
    return fixture.message;
  }

  @override
  Future<void> saveMessage(GroupMessage message) async {
    fixture.writes.add('message.save');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GroupRepository implements GroupRepository {
  _GroupRepository(this.fixture);

  final _Fixture fixture;

  @override
  Future<GroupModel?> getGroup(String id) async {
    fixture.recordRead('group');
    return fixture.group;
  }

  @override
  Future<GroupMember?> getMember(String groupId, String peerId) async {
    fixture.recordRead('member');
    return fixture.member;
  }

  @override
  Future<void> saveGroup(GroupModel group) async {
    fixture.writes.add('group.save');
  }

  @override
  Future<void> saveMember(GroupMember member) async {
    fixture.writes.add('member.save');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MediaRepository implements MediaAttachmentRepository {
  _MediaRepository(this.fixture);

  final _Fixture fixture;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    fixture.recordRead('attachments');
    fixture.requestedAttachmentOwners.add(owner);
    return fixture.attachments;
  }

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    fixture.writes.add('attachment.save');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ContactRepository implements ContactRepository {
  _ContactRepository(this.fixture);

  final _Fixture fixture;

  @override
  Future<ContactModel?> getContact(String peerId) async {
    fixture.recordRead('contact');
    return fixture.contact;
  }

  @override
  Future<void> addContact(ContactModel contact) async {
    fixture.writes.add('contact.add');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

IdentityModel _identity({String peerId = _currentPeerId}) => IdentityModel(
  peerId: peerId,
  publicKey: 'identity-public-key',
  privateKey: 'identity-private-key',
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  createdAt: '2026-07-11T00:00:00.000Z',
  updatedAt: '2026-07-11T00:00:00.000Z',
);

GroupMessage _message() => GroupMessage(
  id: _sourceMessageId,
  groupId: _groupId,
  senderPeerId: _senderPeerId,
  text: '',
  timestamp: DateTime.utc(2026, 7, 11),
  isIncoming: true,
  createdAt: DateTime.utc(2026, 7, 11),
);

GroupModel _group() => GroupModel(
  id: _groupId,
  name: 'Announcements',
  type: GroupType.announcement,
  topicName: 'topic-announcements',
  createdAt: DateTime.utc(2026, 7, 11),
  createdBy: 'group-admin',
  myRole: GroupRole.member,
);

GroupMember _member({
  String groupId = _groupId,
  String peerId = _currentPeerId,
}) => GroupMember(
  groupId: groupId,
  peerId: peerId,
  role: MemberRole.reader,
  joinedAt: DateTime.utc(2026, 7, 11),
);

MediaAttachment _attachment({
  String messageId = _sourceMessageId,
  String mediaType = 'image',
  String mime = 'image/jpeg',
  String downloadStatus = 'pending',
  String? localPath,
  MediaOwnerLane? ownerLane = MediaOwnerLane.group,
}) => MediaAttachment(
  id: 'attachment-$mediaType-$downloadStatus',
  messageId: messageId,
  mime: mime,
  size: 42,
  mediaType: mediaType,
  localPath: localPath,
  downloadStatus: downloadStatus,
  createdAt: '2026-07-11T00:00:00.000Z',
  ownerLane: ownerLane,
);

ContactModel _contact({String peerId = _senderPeerId}) => ContactModel(
  peerId: peerId,
  publicKey: 'contact-public-key',
  rendezvous: '/dns4/example.invalid/tcp/443',
  username: 'Sender',
  signature: 'contact-signature',
  scannedAt: '2026-07-11T00:00:00.000Z',
);

GroupMessageRepositoryImpl _realMessageRepository({
  Future<Map<String, Object?>?> Function(String messageId)? deletionLoader,
}) => GroupMessageRepositoryImpl(
  dbInsertGroupMessage: (_) async {},
  dbLoadGroupMessagesPage: (_, {int limit = 50, int offset = 0}) async =>
      <Map<String, Object?>>[],
  dbLoadGroupMessage: (_) async => null,
  dbLoadLatestGroupMessage: (_) async => null,
  dbUpdateGroupMessageStatus: (id, status) async {},
  dbCountGroupMessages: (_) async => 0,
  dbCountUnreadGroupMessages: (_) async => 0,
  dbCountTotalUnreadGroupMessages: () async => 0,
  dbMarkGroupMessagesAsRead: (_) async => 0,
  dbDeleteGroupMessage: (_) async {},
  dbExistsGroupMessageByContent:
      (groupId, senderPeerId, text, timestamp) async => false,
  dbDeleteGroupMessagesForGroup: (_) async => 0,
  dbLoadGroupThreadSummaries: (_) async => <Map<String, Object?>>[],
  dbLoadGroupMessageLocalDeletionFn: deletionLoader,
);
