import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 236 TC-236-14: the group-forwarding transport boundary is EXACTLY optional
// encrypted-payload metadata plus narrow Go-bridge JSON->options plumbing.
// This source contract is path- and symbol-specific: it pins where the marker
// may live, proves the Go node production carries NO marker-specific code
// (delivery rides the existing encrypted-extra mechanism), and rejects new
// publish primitives, topics, or recipient/key-rule changes hiding behind the
// feature.

const _marker = 'isForwarded';

List<File> _goProductionFiles(String root) {
  return Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) => file.path.endsWith('.go') && !file.path.endsWith('_test.go'),
      )
      .toList(growable: false);
}

void main() {
  test('GMF-14 forwarding changes only approved marker plumbing', () {
    // --- Go side: the ONLY production file that may know the marker is the
    // bridge parameter/option mapping. The node stays marker-agnostic.
    final bridgeFiles = _goProductionFiles('go-mknoon/bridge');
    final nodeFiles = _goProductionFiles('go-mknoon/node');
    expect(bridgeFiles, isNotEmpty);
    expect(nodeFiles, isNotEmpty);

    final goFilesWithMarker = <String>[];
    for (final file in [...bridgeFiles, ...nodeFiles]) {
      final source = file.readAsStringSync();
      if (source.contains(_marker) || source.contains('IsForwarded')) {
        goFilesWithMarker.add(file.path.replaceAll(r'\', '/'));
      }
    }
    expect(
      goFilesWithMarker,
      ['go-mknoon/bridge/bridge.go'],
      reason:
          'only the bridge JSON->options mapping may name the marker; the '
          'node must keep delivering it as a generic encrypted extra',
    );

    // The approved bridge plumbing is the EXACT typed param + shared opts
    // line — not a parallel command or a payload rewrite.
    final bridgeSource = File('go-mknoon/bridge/bridge.go').readAsStringSync();
    expect(
      bridgeSource,
      contains('IsForwarded              bool'),
      reason: 'typed bool param on groupBridgeMessageParams',
    );
    expect(bridgeSource, contains('`json:"isForwarded,omitempty"`'));
    expect(
      bridgeSource,
      contains('opts["isForwarded"] = true'),
      reason: 'one shared opts mapping serves BOTH group message commands',
    );
    expect(
      RegExp(r'opts\["isForwarded"\]').allMatches(bridgeSource),
      hasLength(1),
      reason: 'exactly one opts mapping site',
    );

    // --- Node production keeps the existing encrypted-extra mechanism and
    // does NOT protect (strip) the marker out of received events.
    final pubsubSource = File('go-mknoon/node/pubsub.go').readAsStringSync();
    expect(pubsubSource, contains('func buildGroupMessageExtra'));
    expect(pubsubSource, contains('func isProtectedGroupMessageEventField'));
    expect(
      pubsubSource.contains(_marker),
      isFalse,
      reason: 'the node never special-cases the marker',
    );

    // --- No transport-primitive creep: the Dart group bridge helper speaks
    // the EXACT pre-existing group command set — forwarding added no publish
    // primitive, channel, or topic.
    final helperSource = File(
      'lib/core/bridge/bridge_group_helpers.dart',
    ).readAsStringSync();
    final groupCommands = RegExp(
      r"'cmd':\s*'(group:[a-zA-Z]+)'",
    ).allMatches(helperSource).map((match) => match.group(1)!).toSet();
    expect(
      groupCommands,
      {
        'group:create',
        'group:join',
        'group:acknowledgeRecovery',
        'group:leave',
        'group:publish',
        'group:sendReliable',
        'group:publishReaction',
        'group:updateConfig',
        'group:generateNextKey',
        'group:updateKey',
        'group:inboxStore',
        'group:inboxRetrieve',
        'group:inboxRetrieveCursor',
        'group:historyRepairRange',
      },
      reason:
          'forwarding must not add or remove a group bridge command; if a '
          'DIFFERENT plan legitimately changes this set, update this pin '
          'together with its own transport review',
    );

    // --- Dart side: only the approved group/share lane files may carry the
    // marker into group transport payload maps or consume it at an explicitly
    // reviewed eligibility boundary. (The conversation lane's own marker is
    // plan 232's contract.) Plan 364 must decode the signed marker and exclude
    // forwarded targets from protected reactions and the linked text-only
    // surface; Plan 365's strict fresh-blob producer must likewise reject a
    // forwarded parent before staging custody. Those sites are semantic
    // consumers, not new transport primitives (the exact command and Go-node
    // assertions above remain the transport proof).
    const approvedGroupMarkerFiles = {
      'lib/core/bridge/bridge_group_helpers.dart',
      'lib/features/groups/application/send_group_message_use_case.dart',
      'lib/features/groups/application/handle_incoming_group_message_use_case.dart',
      'lib/features/groups/application/group_message_listener.dart',
      'lib/features/groups/application/group_message_listener_membership_dependent_message_buffer.dart',
      'lib/features/groups/application/protected_group_content_receive.dart',
      'lib/features/groups/application/drain_group_offline_inbox_use_case.dart',
      'lib/features/groups/application/retry_failed_group_messages_use_case.dart',
      'lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart',
      'lib/features/groups/application/send_group_reaction_use_case.dart',
      'lib/features/groups/application/remove_group_reaction_use_case.dart',
      'lib/features/groups/application/group_media_forward_intent.dart',
      'lib/features/groups/application/group_media_forward_policy.dart',
      'lib/features/groups/application/announcement_media_forward_request.dart',
      'lib/features/groups/application/prepared_group_media_blob_custody_coordinator.dart',
      'lib/features/groups/domain/models/group_message.dart',
      'lib/features/groups/presentation/screens/group_conversation_screen.dart',
      'lib/features/groups/presentation/screens/group_conversation_wired.dart',
      'lib/features/groups/presentation/screens/linked_group_conversation_wired.dart',
      'lib/features/share/application/share_batch_delivery_coordinator.dart',
      'lib/features/share/presentation/screens/share_target_picker_wired.dart',
      'lib/features/share/presentation/navigation/share_target_picker_route.dart',
    };
    final groupLaneRoots = [
      Directory('lib/features/groups'),
      Directory('lib/features/share'),
      Directory('lib/core/bridge'),
    ];
    final offenders = <String>[];
    for (final root in groupLaneRoots) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = entity.path.replaceAll(r'\', '/');
        if (!entity.readAsStringSync().contains(_marker)) continue;
        if (!approvedGroupMarkerFiles.contains(normalized)) {
          offenders.add(normalized);
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'unapproved group/share-lane file(s) reference the marker — extend '
          'the transport review before widening the boundary',
    );

    // --- The wire seam stays payload-internal: the Dart helper writes the
    // marker into the message PAYLOAD map (encrypted by Go), pinned by shape.
    expect(
      RegExp(
        r"if \(isForwarded\) \{\n    payload\['isForwarded'\] = true;\n  \}",
      ).allMatches(helperSource),
      hasLength(2),
      reason: 'both group message commands map the marker into the payload',
    );
  });
}
