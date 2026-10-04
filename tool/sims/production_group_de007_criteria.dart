import 'production_catalog_case.dart';

const _key = 'aliceZeroPeer';
const _proof = 'de007ZeroPeerProof';

/// Texts of catalog `de007`, identical to the original harness.
Map<String, ProductionCatalogText> productionDe007Texts(String run) => {
  _key: (role: 'alice', text: 'DE-007 zero-peer durable fallback $run'),
};

const productionDe007Flows = [
  'create',
  'alice-zero-peer',
  'accept-bob',
  'accept-charlie',
];

/// DE-007. Alice creates the group through the UI and sends before Bob or
/// Charlie has joined (both hold only the pending invitation, so the topic
/// has no peer): production `successNoPeers` with inbox custody addressed to
/// both. Each then accepts and stores the message once from the offline
/// inbox, never live.
List<String> validateProductionGroupDe007(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'de007',
      flows: productionDe007Flows,
      verdicts: (c) {
        final sent = c.sentFanout('alice', _key);
        final recipients = (sent?['recipientPeerIds'] as List?) ?? const [];
        bool pendingBefore(String r) {
          final before = proof['${r}BeforeSend'] as Map?;
          return before?['group'] == null &&
              ((before?['pending'] as List?) ?? const []).isNotEmpty;
        }

        Map<String, Object?> receiver(String r) {
          final got = c.received(r, _key);
          return {
            'rowId': 'DE-007',
            'messageId': got?['messageId'],
            'joinedAfterAliceSend':
                pendingBefore(r) && c.finalOf(r)['selfMember'] == true,
            'receivedViaOfflineReplay': got != null && !c.live(r, _key),
            'receivedVisibleMessageOnce': c.finalCount(r, _key) == 1,
            'matchedMessageId':
                got != null && got['messageId'] == sent?['messageId'],
            'matchedSenderPeerId': got?['senderPeerId'] == c.peers['alice'],
          };
        }

        return [
          c.verdict(
            'alice',
            sent: [sent],
            extra: {
              _proof: {
                'rowId': 'DE-007',
                'messageId': sent?['messageId'],
                'sendResultSuccessNoPeers': sent?['outcome'] == 'successNoPeers',
                'inboxStored': sent?['inboxStored'] == true,
                'publishedBeforeReceiversJoined':
                    pendingBefore('bob') && pendingBefore('charlie'),
                'activeRecipientsCovered':
                    recipients.contains(c.peers['bob']) &&
                    recipients.contains(c.peers['charlie']),
                'activeRecipientCount': recipients.length,
              },
            },
          ),
          for (final r in ['bob', 'charlie'])
            c.verdict(
              r,
              received: [c.received(r, _key)],
              extra: {_proof: receiver(r)},
            ),
        ];
      },
    );
