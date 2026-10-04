import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _beforeParent = 'aliceGe024BeforeRemovalParent';
const _removedParent = 'aliceGe024RemovedWindowParent';
const _availableReply = 'bobGe024ReplyAvailable';
const _unavailableReply = 'bobGe024ReplyUnavailable';

/// Texts of catalog `ge024`, identical to the original harness.
Map<String, ProductionCatalogText> productionGe024Texts(String run) => {
  _beforeParent: (
    role: 'alice',
    text: 'GE-024 Alice parent before Charlie removal $run',
  ),
  _removedParent: (
    role: 'alice',
    text: 'GE-024 Alice parent while Charlie removed $run',
  ),
  _availableReply: (
    role: 'bob',
    text: 'GE-024 Bob reply to entitled parent $run',
  ),
  _unavailableReply: (
    role: 'bob',
    text: 'GE-024 Bob reply to removed-window parent $run',
  ),
};

const productionGe024Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-before-parent',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-removed-parent',
  'readd-charlie',
  'charlie-home',
  'accept-charlie-readd',
  'bob-reply-available',
  'bob-reply-unavailable',
  'alice-renders-replies',
  'bob-renders-replies',
  'charlie-renders-replies',
];

/// The original's per-role `ge024QuotedReplyProof`, read from [role]'s final
/// snapshot. `noCrashRenderingUnavailableQuote` (a constant in the original)
/// is the role's own render flow: its chat showed both replies with their
/// quote bars, Charlie's with "Message unavailable" for the removed-window
/// parent.
Map<String, Object?> _quoteProof(
  ProductionCatalogCase c,
  String role, {
  required Map ids,
  int removedWindowPlaintextCount = 0,
}) {
  final f = c.finalOf(role);
  String? quoteOf(String key) {
    final rows = productionCatalogRows(f, key);
    return rows.length == 1 ? rows.single['quotedMessageId'] as String? : null;
  }

  final charlie = '${c.peers['charlie']}';
  final members = c.members(f);
  final available = quoteOf(_availableReply);
  final unavailable = quoteOf(_unavailableReply);
  final flows = (c.proof['flows'] as List).cast<String>();
  return {
    'quotePropagationProof':
        available == ids[_beforeParent] && unavailable == ids[_removedParent],
    'availableParentMessageId': ids[_beforeParent],
    'removedWindowParentMessageId': ids[_removedParent],
    'availableReplyMessageId': ids[_availableReply],
    'unavailableReplyMessageId': ids[_unavailableReply],
    'availableReplyQuotedMessageId': available,
    'unavailableReplyQuotedMessageId': unavailable,
    'availableReplyHasExpectedQuote': available == ids[_beforeParent],
    'unavailableReplyHasExpectedQuote': unavailable == ids[_removedParent],
    'availableParentPresent': c.finalCount(role, _beforeParent) == 1,
    'unavailableParentMissing': c.finalCount(role, _removedParent) == 0,
    'removedWindowPlaintextCount': removedWindowPlaintextCount,
    'noUnavailableParentPlaintext': removedWindowPlaintextCount == 0,
    'noCrashRenderingUnavailableQuote': flows.contains('$role-renders-replies'),
    'removedPeerId': charlie,
    'finalIncludesRemovedPeer': members.contains(charlie),
    'finalMemberPeerIds': members.toList()..sort(),
    'finalEpoch': c.epoch(role),
  };
}

List<String> validateProductionGroupGe024(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'ge024',
      flows: productionGe024Flows,
      verdicts: (c) {
        final aliceSent = [
          c.sent('alice', _beforeParent),
          c.sent('alice', _removedParent),
        ];
        final bobSent = [
          c.sent('bob', _availableReply),
          c.sent('bob', _unavailableReply),
        ];
        final ids = {
          _beforeParent: aliceSent[0]?['messageId'],
          _removedParent: aliceSent[1]?['messageId'],
          _availableReply: bobSent[0]?['messageId'],
          _unavailableReply: bobSent[1]?['messageId'],
        };
        // Charlie's plaintext copies of the removed-window parent: in the
        // window (five seconds after Alice's send, as the original counts)
        // and at the end.
        final window = productionCatalogRows(
          c.stage('charlieRemovedWindow', 'charlie'),
          _removedParent,
        ).length;
        final plaintext = window + c.finalCount('charlie', _removedParent);
        return [
          c.verdict(
            'alice',
            sent: aliceSent,
            received: [
              c.received('alice', _availableReply),
              c.received('alice', _unavailableReply),
            ],
            extra: {'ge024QuotedReplyProof': _quoteProof(c, 'alice', ids: ids)},
          ),
          c.verdict(
            'bob',
            sent: bobSent,
            received: [
              c.received('bob', _beforeParent),
              c.received('bob', _removedParent),
            ],
            extra: {'ge024QuotedReplyProof': _quoteProof(c, 'bob', ids: ids)},
          ),
          c.verdict(
            'charlie',
            received: [
              c.received('charlie', _beforeParent),
              c.received('charlie', _availableReply),
              c.received('charlie', _unavailableReply),
            ],
            extra: {
              'ge024QuotedReplyProof': _quoteProof(
                c,
                'charlie',
                ids: ids,
                removedWindowPlaintextCount: plaintext,
              ),
            },
          ),
        ];
      },
    );
