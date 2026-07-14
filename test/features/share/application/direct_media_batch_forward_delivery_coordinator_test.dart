import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/share/application/direct_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';

void main() {
  test(
    'source denial precedes contact lookup and every ordinary delivery call',
    () async {
      final events = <String>[];
      final contacts = _RecordingContactRepository(events: events)
        ..addTestContact(_contact('contact-alpha'));
      var strictCalls = 0;
      DirectMediaLibraryBatchForwardDraft? revalidatedDraft;
      final coordinator = DirectMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch:
            ({required contactPeerId, required draft}) async {
              events.add('source');
              revalidatedDraft = draft;
              return const DirectMediaLibraryBatchForwardResult.denied(
                DirectMediaLibraryBatchForwardDenial.sourceNotEligible,
              );
            },
        contactRepository: contacts,
        deliverStrict:
            ({required shareIntent, required contacts, onProgress}) async {
              strictCalls++;
              return const ShareBatchDeliveryResult(results: []);
            },
      );
      final first = _item(
        messageId: 'source-message-one',
        attachmentId: 'source-attachment-one',
        path: '/private/source-one.jpg',
        caption: 'first caption',
        token: 'opaque-token-one',
      );
      final second = _item(
        messageId: 'source-message-two',
        attachmentId: 'source-attachment-two',
        path: '/private/source-two.jpg',
        caption: 'second caption',
        token: 'opaque-token-two',
      );
      final draft = DirectMediaLibraryBatchForwardDraft(items: [first, second]);

      for (final invalid in <List<String>>[
        const [],
        const ['   '],
        const ['contact-alpha', 'contact-alpha'],
      ]) {
        final result = await coordinator.deliverInitial(
          sourceContactPeerId: 'source-contact',
          draft: draft,
          contactPeerIds: invalid,
        );
        expect(
          result.denial,
          DirectMediaBatchForwardAttemptDenial.invalidRequest,
        );
        expect(result.matrix, isNull);
        expect(result.newlyAttemptedCellCount, 0);
      }
      expect(events, isEmpty, reason: 'invalid targets must precede source IO');

      final denied = await coordinator.deliverInitial(
        sourceContactPeerId: 'source-contact',
        draft: draft,
        contactPeerIds: const ['contact-alpha'],
      );
      expect(
        denied.denial,
        DirectMediaBatchForwardAttemptDenial.sourceUnavailable,
      );
      expect(denied.matrix, isNull);
      expect(events, ['source']);
      expect(contacts.getContactCalls, isEmpty);
      expect(strictCalls, 0);

      final prior = DirectMediaBatchForwardMatrix(
        cells: [
          DirectMediaBatchForwardCellResult(
            key: DirectMediaBatchForwardCellKey(
              sourceIdentity: first.identity,
              contactPeerId: 'contact-alpha',
            ),
            status: DirectMediaBatchForwardCellStatus.sent,
          ),
          DirectMediaBatchForwardCellResult(
            key: DirectMediaBatchForwardCellKey(
              sourceIdentity: second.identity,
              contactPeerId: 'contact-alpha',
            ),
            status: DirectMediaBatchForwardCellStatus.failed,
          ),
        ],
      );
      events.clear();
      final retryDenied = await coordinator.retryFailed(
        sourceContactPeerId: 'source-contact',
        draft: draft,
        priorMatrix: prior,
      );

      expect(
        retryDenied.denial,
        DirectMediaBatchForwardAttemptDenial.sourceUnavailable,
      );
      expect(identical(retryDenied.matrix, prior), isTrue);
      expect(retryDenied.newlyAttemptedCellCount, 0);
      expect(events, ['source']);
      expect(revalidatedDraft!.items.map((item) => item.identity), [
        second.identity,
      ]);
      expect(contacts.getContactCalls, isEmpty);
      expect(strictCalls, 0);
    },
  );

  test(
    'two canonical sources by two active contacts produce four source-major ordinary cells',
    () async {
      final events = <String>[];
      final alpha = _contact('contact-alpha', username: 'Alpha current');
      final beta = _contact('contact-beta', username: 'Beta current');
      final contacts = _RecordingContactRepository(events: events)
        ..responses.addAll({alpha.peerId: alpha, beta.peerId: beta});
      final olderSibling = _item(
        messageId: 'same-parent-message',
        attachmentId: 'attachment-older',
        path: '/current/older.jpg',
        caption: '',
        token: 'opaque-token-older',
      );
      final newerSibling = _item(
        messageId: 'same-parent-message',
        attachmentId: 'attachment-newer',
        path: '/current/newer.jpg',
        caption: 'edited newer caption',
        token: 'opaque-token-newer',
      );
      final input = DirectMediaLibraryBatchForwardDraft(
        items: [olderSibling, newerSibling],
      );
      final canonical = DirectMediaLibraryBatchForwardDraft(
        items: [newerSibling, olderSibling],
      );
      final calls = <_StrictCall>[];
      final progress = <DirectMediaBatchForwardProgress>[];
      final coordinator = DirectMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch:
            ({required contactPeerId, required draft}) async {
              events.add('source');
              expect(contactPeerId, 'source-contact');
              expect(draft.items.map((item) => item.identity), [
                olderSibling.identity,
                newerSibling.identity,
              ]);
              return DirectMediaLibraryBatchForwardResult.ready(canonical);
            },
        contactRepository: contacts,
        deliverStrict:
            ({required shareIntent, required contacts, onProgress}) async {
              events.add('strict:${shareIntent.filePaths.single}');
              calls.add(_StrictCall(shareIntent, contacts));
              return ShareBatchDeliveryResult(
                results: [
                  for (final contact in contacts)
                    _ordinaryResult(
                      contact,
                      DirectMediaBatchForwardCellStatus.sent,
                    ),
                ],
              );
            },
      );

      final result = await coordinator.deliverInitial(
        sourceContactPeerId: 'source-contact',
        draft: input,
        contactPeerIds: [beta.peerId, alpha.peerId],
        onProgress: progress.add,
      );

      expect(events.take(4), [
        'source',
        'contact:${beta.peerId}',
        'contact:${alpha.peerId}',
        'strict:${newerSibling.resolvedPath}',
      ]);
      expect(calls, hasLength(2));
      for (var index = 0; index < calls.length; index++) {
        final item = canonical.items[index];
        final call = calls[index];
        expect(call.shareIntent.filePaths, [item.resolvedPath]);
        expect(
          call.shareIntent.text,
          item.caption.isEmpty ? isNull : item.caption,
        );
        expect(
          call.shareIntent.forwardProvenance!.operationDedupKey,
          item.forwardProvenance.operationDedupKey,
        );
        expect(call.contacts.map((contact) => contact.peerId), [
          beta.peerId,
          alpha.peerId,
        ]);
      }
      expect(
        result.matrix!.cells.map(
          (cell) =>
              '${cell.key.sourceIdentity.attachmentId}/${cell.key.contactPeerId}',
        ),
        [
          'attachment-newer/${beta.peerId}',
          'attachment-newer/${alpha.peerId}',
          'attachment-older/${beta.peerId}',
          'attachment-older/${alpha.peerId}',
        ],
      );
      expect(result.matrix!.sentCount, 4);
      expect(result.matrix!.fullySettledSourceIdentities, {
        newerSibling.identity,
        olderSibling.identity,
      });
      expect(result.matrix!.failedSourceIdentities, isEmpty);
      expect(result.newlyAttemptedCellCount, 4);
      expect(progress, isNotEmpty);
      expect(progress.last.completedCellCount, 4);
      expect(progress.last.totalCellCount, 4);
    },
  );

  test(
    'current direct contact qualification fails invalid cells and continues valid contacts',
    () async {
      final events = <String>[];
      final valid = _contact('contact-valid', username: 'Current valid');
      final archived = _contact('contact-archived', isArchived: true);
      final blocked = _contact('contact-blocked', isBlocked: true);
      final mismatched = _contact('contact-replacement');
      final contacts = _RecordingContactRepository(events: events)
        ..responses.addAll({
          valid.peerId: valid,
          'contact-missing': null,
          'contact-mismatch': mismatched,
          archived.peerId: archived,
          blocked.peerId: blocked,
        })
        ..throwingPeerIds.add('contact-throwing');
      final source = _item(
        messageId: 'source-message',
        attachmentId: 'source-attachment',
        path: '/current/source.jpg',
        caption: 'caption',
        token: 'opaque-source-token',
      );
      var strictCalls = 0;
      final coordinator = DirectMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch:
            ({required contactPeerId, required draft}) async =>
                DirectMediaLibraryBatchForwardResult.ready(draft),
        contactRepository: contacts,
        deliverStrict:
            ({required shareIntent, required contacts, onProgress}) async {
              strictCalls++;
              expect(contacts.map((contact) => contact.peerId), [valid.peerId]);
              expect(contacts.single.username, 'Current valid');
              return ShareBatchDeliveryResult(
                results: [
                  _ordinaryResult(
                    contacts.single,
                    DirectMediaBatchForwardCellStatus.sent,
                  ),
                ],
              );
            },
      );
      final requested = [
        valid.peerId,
        'contact-missing',
        'contact-mismatch',
        archived.peerId,
        blocked.peerId,
        'contact-throwing',
      ];

      final result = await coordinator.deliverInitial(
        sourceContactPeerId: 'source-contact',
        draft: DirectMediaLibraryBatchForwardDraft(items: [source]),
        contactPeerIds: requested,
      );

      expect(contacts.getContactCalls, requested);
      expect(strictCalls, 1);
      expect(result.matrix!.cells, hasLength(requested.length));
      expect(
        result.matrix!.cells.map((cell) => cell.key.contactPeerId),
        requested,
      );
      expect(result.matrix!.cells.map((cell) => cell.status), [
        DirectMediaBatchForwardCellStatus.sent,
        DirectMediaBatchForwardCellStatus.failed,
        DirectMediaBatchForwardCellStatus.failed,
        DirectMediaBatchForwardCellStatus.failed,
        DirectMediaBatchForwardCellStatus.failed,
        DirectMediaBatchForwardCellStatus.failed,
      ]);

      final noneValidContacts = _RecordingContactRepository()
        ..responses.addAll({
          'contact-missing': null,
          'contact-mismatch': mismatched,
        });
      var allInvalidStrictCalls = 0;
      final allInvalid = DirectMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch:
            ({required contactPeerId, required draft}) async =>
                DirectMediaLibraryBatchForwardResult.ready(draft),
        contactRepository: noneValidContacts,
        deliverStrict:
            ({required shareIntent, required contacts, onProgress}) async {
              allInvalidStrictCalls++;
              return const ShareBatchDeliveryResult(results: []);
            },
      );
      final allInvalidResult = await allInvalid.deliverInitial(
        sourceContactPeerId: 'source-contact',
        draft: DirectMediaLibraryBatchForwardDraft(items: [source]),
        contactPeerIds: const ['contact-missing', 'contact-mismatch'],
      );
      expect(allInvalidStrictCalls, 0);
      expect(allInvalidResult.matrix!.failedCount, 2);
    },
  );

  test(
    'ordinary sent queued failed and malformed results form one complete truthful matrix',
    () async {
      final alpha = _contact('contact-alpha');
      final beta = _contact('contact-beta');
      final foreign = _contact('contact-foreign');
      final contacts = _RecordingContactRepository()
        ..responses.addAll({alpha.peerId: alpha, beta.peerId: beta});
      final sources = [
        _item(
          messageId: 'message-one',
          attachmentId: 'attachment-one',
          path: '/current/one.jpg',
          caption: 'one',
          token: 'token-one',
        ),
        _item(
          messageId: 'message-two',
          attachmentId: 'attachment-two',
          path: '/current/two.jpg',
          caption: 'two',
          token: 'token-two',
        ),
        _item(
          messageId: 'message-three',
          attachmentId: 'attachment-three',
          path: '/current/three.jpg',
          caption: 'three',
          token: 'token-three',
        ),
        _item(
          messageId: 'message-four',
          attachmentId: 'attachment-four',
          path: '/current/four.jpg',
          caption: 'four',
          token: 'token-four',
        ),
      ];
      var strictCall = 0;
      final coordinator = DirectMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch:
            ({required contactPeerId, required draft}) async =>
                DirectMediaLibraryBatchForwardResult.ready(draft),
        contactRepository: contacts,
        deliverStrict:
            ({required shareIntent, required contacts, onProgress}) async {
              strictCall++;
              if (strictCall == 3) {
                throw StateError('ordinary-secret-that-must-not-escape');
              }
              if (strictCall == 1) {
                return ShareBatchDeliveryResult(
                  results: [
                    _ordinaryResult(
                      alpha,
                      DirectMediaBatchForwardCellStatus.sent,
                    ),
                    _ordinaryResult(
                      beta,
                      DirectMediaBatchForwardCellStatus.queued,
                    ),
                  ],
                );
              }
              if (strictCall == 2) {
                return ShareBatchDeliveryResult(
                  results: [
                    _ordinaryResult(
                      alpha,
                      DirectMediaBatchForwardCellStatus.failed,
                      detail: 'sensitive ordinary detail',
                    ),
                    _ordinaryResult(
                      foreign,
                      DirectMediaBatchForwardCellStatus.sent,
                    ),
                    ShareBatchTargetResult(
                      target: ShareTargetSelection.group(
                        _group('adversarial-group'),
                      ),
                      status: ShareBatchTargetStatus.sent,
                      detail: 'foreign group detail',
                    ),
                  ],
                );
              }
              return ShareBatchDeliveryResult(
                results: [
                  _ordinaryResult(
                    alpha,
                    DirectMediaBatchForwardCellStatus.sent,
                  ),
                  _ordinaryResult(
                    alpha,
                    DirectMediaBatchForwardCellStatus.queued,
                  ),
                  _ordinaryResult(beta, DirectMediaBatchForwardCellStatus.sent),
                ],
              );
            },
      );

      final result = await coordinator.deliverInitial(
        sourceContactPeerId: 'source-contact',
        draft: DirectMediaLibraryBatchForwardDraft(items: sources),
        contactPeerIds: [alpha.peerId, beta.peerId],
      );

      expect(
        strictCall,
        4,
        reason: 'a thrown source must not abort later sources',
      );
      expect(result.matrix!.cells, hasLength(8));
      expect(result.matrix!.cells.map((cell) => cell.status), [
        DirectMediaBatchForwardCellStatus.sent,
        DirectMediaBatchForwardCellStatus.queued,
        DirectMediaBatchForwardCellStatus.failed,
        DirectMediaBatchForwardCellStatus.failed,
        DirectMediaBatchForwardCellStatus.failed,
        DirectMediaBatchForwardCellStatus.failed,
        DirectMediaBatchForwardCellStatus.failed,
        DirectMediaBatchForwardCellStatus.sent,
      ]);
      expect(result.matrix!.sentCount, 2);
      expect(result.matrix!.queuedCount, 1);
      expect(result.matrix!.failedCount, 5);
      expect(
        result.matrix!.cells
            .map(
              (cell) =>
                  '${cell.key.sourceIdentity.messageId}/${cell.key.contactPeerId}',
            )
            .toSet()
            .length,
        8,
      );
      expect(
        result.matrix.toString(),
        isNot(contains('sensitive ordinary detail')),
      );
      expect(
        result.matrix.toString(),
        isNot(contains('ordinary-secret-that-must-not-escape')),
      );
      expect(
        result.matrix!.cells
            .where(
              (cell) =>
                  cell.key.sourceIdentity == sources.last.identity &&
                  cell.key.contactPeerId == alpha.peerId,
            )
            .single
            .status,
        DirectMediaBatchForwardCellStatus.failed,
        reason: 'duplicate requested results fail closed',
      );
    },
  );

  test(
    'failed-cell retry is sparse and preserves each source caption and token',
    () async {
      final alpha = _contact('contact-alpha');
      final beta = _contact('contact-beta');
      final contacts = _RecordingContactRepository()
        ..responses.addAll({alpha.peerId: alpha, beta.peerId: beta});
      final first = _item(
        messageId: 'message-first',
        attachmentId: 'attachment-first',
        path: '/current/first.jpg',
        caption: '',
        token: 'original-token-first',
      );
      final second = _item(
        messageId: 'message-second',
        attachmentId: 'attachment-second',
        path: '/current/second.jpg',
        caption: 'latest edited second',
        token: 'original-token-second',
      );
      final settledOnly = _item(
        messageId: 'message-settled',
        attachmentId: 'attachment-settled',
        path: '/current/settled.jpg',
        caption: 'settled caption',
        token: 'original-token-settled',
      );
      final draft = DirectMediaLibraryBatchForwardDraft(
        items: [first, second, settledOnly],
      );
      DirectMediaLibraryBatchForwardDraft? retryDraft;
      final calls = <_StrictCall>[];
      final coordinator = DirectMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch:
            ({required contactPeerId, required draft}) async {
              retryDraft = draft;
              return DirectMediaLibraryBatchForwardResult.ready(draft);
            },
        contactRepository: contacts,
        deliverStrict:
            ({required shareIntent, required contacts, onProgress}) async {
              calls.add(_StrictCall(shareIntent, contacts));
              return ShareBatchDeliveryResult(
                results: [
                  _ordinaryResult(
                    contacts.single,
                    calls.length == 1
                        ? DirectMediaBatchForwardCellStatus.sent
                        : DirectMediaBatchForwardCellStatus.queued,
                  ),
                ],
              );
            },
      );
      DirectMediaBatchForwardCellResult cell(
        DirectMediaLibraryBatchForwardItemDraft item,
        ContactModel contact,
        DirectMediaBatchForwardCellStatus status,
      ) => DirectMediaBatchForwardCellResult(
        key: DirectMediaBatchForwardCellKey(
          sourceIdentity: item.identity,
          contactPeerId: contact.peerId,
        ),
        status: status,
      );
      final prior = DirectMediaBatchForwardMatrix(
        cells: [
          cell(first, alpha, DirectMediaBatchForwardCellStatus.sent),
          cell(first, beta, DirectMediaBatchForwardCellStatus.failed),
          cell(second, alpha, DirectMediaBatchForwardCellStatus.failed),
          cell(second, beta, DirectMediaBatchForwardCellStatus.queued),
          cell(settledOnly, alpha, DirectMediaBatchForwardCellStatus.sent),
          cell(settledOnly, beta, DirectMediaBatchForwardCellStatus.sent),
        ],
      );

      final result = await coordinator.retryFailed(
        sourceContactPeerId: 'source-contact',
        draft: draft,
        priorMatrix: prior,
      );

      expect(retryDraft!.items.map((item) => item.identity), [
        first.identity,
        second.identity,
      ]);
      expect(retryDraft!.items.map((item) => item.caption), [
        '',
        'latest edited second',
      ]);
      expect(
        retryDraft!.items.map(
          (item) => item.forwardProvenance.operationDedupKey,
        ),
        ['original-token-first', 'original-token-second'],
      );
      expect(contacts.getContactCalls, [beta.peerId, alpha.peerId]);
      expect(calls, hasLength(2));
      expect(calls[0].contacts.map((contact) => contact.peerId), [beta.peerId]);
      expect(calls[0].shareIntent.text, isNull);
      expect(
        calls[0].shareIntent.forwardProvenance!.operationDedupKey,
        'original-token-first',
      );
      expect(calls[1].contacts.map((contact) => contact.peerId), [
        alpha.peerId,
      ]);
      expect(calls[1].shareIntent.text, 'latest edited second');
      expect(
        calls[1].shareIntent.forwardProvenance!.operationDedupKey,
        'original-token-second',
      );
      expect(result.newlyAttemptedCellCount, 2);
      expect(result.matrix!.cells.map((cell) => cell.status), [
        DirectMediaBatchForwardCellStatus.sent,
        DirectMediaBatchForwardCellStatus.sent,
        DirectMediaBatchForwardCellStatus.queued,
        DirectMediaBatchForwardCellStatus.queued,
        DirectMediaBatchForwardCellStatus.sent,
        DirectMediaBatchForwardCellStatus.sent,
      ]);
      expect(
        calls.expand((call) => call.contacts).map((contact) => contact.peerId),
        [beta.peerId, alpha.peerId],
        reason: 'retry must not expand crossed failures into a Cartesian send',
      );

      final readsBeforeNoOp = contacts.getContactCalls.length;
      final callsBeforeNoOp = calls.length;
      final noOp = await coordinator.retryFailed(
        sourceContactPeerId: 'source-contact',
        draft: draft,
        priorMatrix: result.matrix!,
      );
      expect(noOp.newlyAttemptedCellCount, 0);
      expect(identical(noOp.matrix, result.matrix), isTrue);
      expect(contacts.getContactCalls, hasLength(readsBeforeNoOp));
      expect(calls, hasLength(callsBeforeNoOp));
    },
  );

  test(
    'delivery matrix and diagnostics expose counts and outcomes only',
    () async {
      const secretMessage = 'secret-message-identity';
      const secretAttachment = 'secret-attachment-identity';
      const secretContact = 'secret-contact-identity';
      const secretCaption = 'secret caption payload';
      const secretPath = '/private/secret-path.jpg';
      const secretToken = 'secret-operation-token';
      const secretError = 'secret ordinary exception';
      final item = _item(
        messageId: secretMessage,
        attachmentId: secretAttachment,
        path: secretPath,
        caption: secretCaption,
        token: secretToken,
      );
      final contact = _contact(secretContact, username: 'secret username');
      final contacts = _RecordingContactRepository()
        ..responses[secretContact] = contact;
      final coordinator = DirectMediaBatchForwardDeliveryCoordinator(
        revalidateForDispatch:
            ({required contactPeerId, required draft}) async =>
                DirectMediaLibraryBatchForwardResult.ready(draft),
        contactRepository: contacts,
        deliverStrict:
            ({required shareIntent, required contacts, onProgress}) async {
              throw StateError(secretError);
            },
      );
      final attempt = await coordinator.deliverInitial(
        sourceContactPeerId: 'source-contact',
        draft: DirectMediaLibraryBatchForwardDraft(items: [item]),
        contactPeerIds: const [secretContact],
      );
      final matrix = attempt.matrix!;
      final completion = DirectMediaBatchForwardCompletion.fromMatrix(matrix);
      final launch = DirectMediaBatchForwardLibraryLaunchResult.completed(
        completion,
      );
      const progress = DirectMediaBatchForwardProgress(
        completedCellCount: 0,
        totalCellCount: 1,
        sourceOrdinal: 1,
        sourceCount: 1,
        phase: DirectMediaBatchForwardProgressPhase.uploading,
      );
      final diagnosticValues = <Object>[
        matrix.cells.single.key,
        matrix.cells.single,
        matrix,
        attempt,
        progress,
        completion,
        launch,
      ];
      for (final value in diagnosticValues) {
        final diagnostic = value.toString();
        for (final secret in const [
          secretMessage,
          secretAttachment,
          secretContact,
          secretCaption,
          secretPath,
          secretToken,
          secretError,
          'secret username',
        ]) {
          expect(
            diagnostic,
            isNot(contains(secret)),
            reason: '$value leaked data',
          );
        }
      }
      expect(matrix.cells.single.key.sourceIdentity, item.identity);
      expect(matrix.cells.single.key.contactPeerId, secretContact);
      expect(matrix.failedCount, 1);
      expect(completion.fullySettledSourceIdentities, isEmpty);
      expect(completion.failedSourceIdentities, {item.identity});
      expect(
        launch.status,
        DirectMediaBatchForwardLibraryLaunchStatus.completed,
      );
      expect(launch.isCompleted, isTrue);
    },
  );
}

class _RecordingContactRepository extends InMemoryContactRepository {
  _RecordingContactRepository({this.events});

  final List<String>? events;
  final Map<String, ContactModel?> responses = <String, ContactModel?>{};
  final Set<String> throwingPeerIds = <String>{};
  final List<String> getContactCalls = <String>[];

  @override
  Future<ContactModel?> getContact(String peerId) async {
    getContactCalls.add(peerId);
    events?.add('contact:$peerId');
    if (throwingPeerIds.contains(peerId)) {
      throw StateError('contact lookup failed');
    }
    if (responses.containsKey(peerId)) {
      return responses[peerId];
    }
    return super.getContact(peerId);
  }
}

class _StrictCall {
  const _StrictCall(this.shareIntent, this.contacts);

  final ShareIntent shareIntent;
  final List<ContactModel> contacts;
}

DirectMediaLibraryBatchForwardItemDraft _item({
  required String messageId,
  required String attachmentId,
  required String path,
  required String caption,
  required String token,
}) => DirectMediaLibraryBatchForwardItemDraft(
  identity: DirectReceivedMediaActionIdentity(
    messageId: messageId,
    attachmentId: attachmentId,
  ),
  resolvedPath: path,
  parentTimestamp: '2026-07-11T12:00:00.000Z',
  caption: caption,
  forwardProvenance: ForwardProvenance(operationDedupKey: token),
);

ContactModel _contact(
  String peerId, {
  String? username,
  bool isArchived = false,
  bool isBlocked = false,
}) => ContactModel(
  peerId: peerId,
  publicKey: 'public-$peerId',
  rendezvous: '/dns4/relay/tcp/443',
  username: username ?? 'User $peerId',
  signature: 'signature-$peerId',
  scannedAt: '2026-07-11T12:00:00.000Z',
  mlKemPublicKey: 'mlkem-$peerId',
  isArchived: isArchived,
  isBlocked: isBlocked,
);

GroupModel _group(String id) => GroupModel(
  id: id,
  name: 'Group $id',
  type: GroupType.chat,
  topicName: 'topic-$id',
  createdAt: DateTime.utc(2026, 7, 11),
  createdBy: 'creator-peer',
  myRole: GroupRole.admin,
);

ShareBatchTargetResult _ordinaryResult(
  ContactModel contact,
  DirectMediaBatchForwardCellStatus status, {
  String detail = 'ordinary detail',
}) => ShareBatchTargetResult(
  target: ShareTargetSelection.contact(contact),
  status: switch (status) {
    DirectMediaBatchForwardCellStatus.sent => ShareBatchTargetStatus.sent,
    DirectMediaBatchForwardCellStatus.queued => ShareBatchTargetStatus.queued,
    DirectMediaBatchForwardCellStatus.failed => ShareBatchTargetStatus.failed,
  },
  detail: detail,
);
