import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 115 Phase 1.2 — G4 enforcement: allowed 'delivered' minting sites.
///
/// A sender-side 1:1 message row may carry status 'delivered' ONLY after
/// receiver confirmation (doc 115 §3, G4). This source-scan invariant
/// enumerates every production write of `status: 'delivered'` /
/// `toStatus: 'delivered'` / `'status': 'delivered'` under lib/ and asserts
/// the set is EXACTLY the allowed minting sites. An untested call site
/// (migration-style backfill, future feature) cannot silently mint
/// 'delivered' without breaking this test.
///
/// Scan-scope decisions (pinned at authoring, per doc 115 Phase 1.2):
/// - `lib/core/database/migrations/` is EXCLUDED: migration
///   015_message_status_cleanup upgrades legacy 'queued' rows to 'delivered'
///   on historical data via SQL; migration-scope writes are not live minting.
/// - Comment lines (`//`, `///`) are excluded — doc comments mention status
///   strings without writing them.
/// - Matches are counted per file. Counts must match EXACTLY: a new site in
///   an allowed file still fails the scan and must be reviewed against G4.
void main() {
  final deliveredWritePatterns = <RegExp>[
    RegExp(r"(?<![A-Za-z_$])status: 'delivered'"),
    RegExp(r"(?<![A-Za-z_$])toStatus: 'delivered'"),
    RegExp(r"(?<![A-Za-z_$])'status': 'delivered'"),
  ];

  Map<String, int> scanDeliveredWrites() {
    final counts = <String, int>{};
    final libDir = Directory('lib');
    final files =
        libDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.contains('lib/core/database/migrations/'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      var fileCount = 0;
      for (final line in lines) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        for (final pattern in deliveredWritePatterns) {
          fileCount += pattern.allMatches(line).length;
        }
      }
      if (fileCount > 0) {
        counts[file.path] = fileCount;
      }
    }
    return counts;
  }

  test(
    'production code mints status delivered only at the enumerated receiver-confirmation sites',
    () {
      // G4 allowed minting sites + pinned out-of-scope writers. Every entry is
      // deliberate; adding a 'delivered' write anywhere in lib/ (outside
      // migrations) MUST update this map and pass review against G4.
      const expected = <String, int>{
        // (a) the delivery-receipt apply — receiver-confirmed by definition
        // (the receipt is emitted after the receiver's durable persist).
        // Two conditionalTransitionStatus calls: 'inboxed'→'delivered' and
        // the lost-ack 'sent'→'delivered' repair.
        'lib/features/conversation/application/handle_delivery_receipt_use_case.dart':
            2,
        // (b) the live deferred-ack branch of _persistOutgoingSendResult —
        // Go withholds the wire ack until the receiver durably stages
        // (node.go deferred direct ack), so this IS receiver confirmation.
        // Site (c) the LAN committed-ack branch joins when doc 114 P1-3 land.
        'lib/features/conversation/application/send_chat_message_use_case.dart':
            1,
        // (b′) the live deferred-ack acked branch of
        // _persistOutgoingDeleteResult — same durable-staging bar as (b).
        'lib/features/conversation/application/delete_message_use_case.dart': 1,
        // (removed by 125, F6-residue): retry_failed_messages_use_case.dart no
        // longer mints terminal 'delivered' on relay custody — both the
        // store-success and already-inbox outcomes now write 'inboxed' (envelope
        // retained), riding the custody sweep + DeliveryReceiptListener for the
        // receiver-confirmed 'delivered'. Count is now 0 (entry dropped).
        // Receiver-side writers marking INCOMING rows 'delivered' — not
        // sender-side custody minting; G4 scopes to outgoing truthfulness.
        'lib/features/conversation/application/handle_incoming_chat_message_use_case.dart':
            5,
        'lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart':
            1,
        // Local/system row writers: no transport, terminal by construction.
        'lib/features/introduction/application/insert_intro_system_message.dart':
            1,
        'lib/features/groups/application/group_membership_timeline_message.dart':
            6,
        'lib/features/groups/application/group_message_listener.dart': 3,
        'lib/smoke_test_messages.dart': 1,
      };

      final actual = scanDeliveredWrites();

      expect(
        actual,
        expected,
        reason:
            'Unexpected `status: \'delivered\'` write site(s). A sender-side '
            "1:1 row may be minted 'delivered' only on receiver confirmation "
            '(G4, doc 115). Review the new site against the allowed minting '
            'sites before whitelisting it here.',
      );
    },
  );

  // 115 Phase 1.6 — status-string census pin (green-on-arrival, D-1).
  //
  // Documents the D-1 decision: 'pending' is RENDER-ONLY for 1:1 message
  // status (letter_card.dart consumes it; no production writer exists), so
  // minting the distinct machine-meaningful status 'inboxed' cannot collide
  // with legacy 'pending' semantics. Scope: lib/features/conversation/ —
  // group/post tables have their own status models (group messages
  // legitimately write 'pending') and are out of D-1 scope.
  test(
    "live message status strings are exactly {sending, sent, failed, delivered, inboxed, queued(legacy read-only)} and nothing writes 'pending'",
    () {
      final statusWritePatterns = <RegExp>[
        RegExp(r"(?<![A-Za-z_$])status: '([a-z_]+)'"),
        RegExp(r"(?<![A-Za-z_$])'status': '([a-z_]+)'"),
      ];
      const allowed = <String>{
        'sending',
        'sent',
        'failed',
        'delivered',
        'inboxed',
        // Legacy: written only as a pre-encrypt log label in
        // send_chat_message_use_case.dart (logChatOutgoing); rows are never
        // persisted 'queued' (migration 015 cleaned historical rows).
        'queued',
      };

      final written = <String>{};
      final conversationDir = Directory('lib/features/conversation');
      final files = conversationDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in files) {
        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) continue;
          for (final pattern in statusWritePatterns) {
            for (final match in pattern.allMatches(line)) {
              written.add(match.group(1)!);
            }
          }
        }
      }

      expect(
        written.difference(allowed),
        isEmpty,
        reason:
            'A new 1:1 message status string was introduced. The status '
            'model is pinned by doc 115 D-1 — extend the census ONLY with a '
            'reviewed design decision.',
      );
      expect(
        written,
        isNot(contains('pending')),
        reason:
            "D-1 (doc 115): 'pending' must stay render-only. If production "
            "code starts writing 'pending', revisit D-1 BEFORE shipping — "
            "that is this pin's job.",
      );
    },
  );
}
