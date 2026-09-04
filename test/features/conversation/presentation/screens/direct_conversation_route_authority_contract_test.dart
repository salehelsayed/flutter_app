import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/config/direct_linked_media_fanout_flag.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/features/contacts/application/direct_contact_device_trust.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_conversation_route_authority.dart';
import 'package:flutter_test/flutter_test.dart';

/// 362 route-composition census.
///
/// The shipped bypass was a WIRING defect, not a behaviour defect: the linked
/// fanout authority, the device-trust capability and the modality gate reached
/// exactly ONE of the production `ConversationWired` pushes (the
/// notification-tap route), so opening the same chat from Feed, Orbit, Posts or
/// the first-time experience produced a screen with no fanout authority, an
/// inert trust capability and the allow-everything modality default.
///
/// No behavioural test caught it because each route looked correct in
/// isolation. This is therefore a COMPUTED census — it discovers construction
/// sites rather than checking a fixed list, so a newly added route that forgets
/// the authority fails here instead of shipping silently.
void main() {
  const wiredPath =
      'lib/features/conversation/presentation/screens/conversation_wired.dart';
  const authorityPath =
      'lib/features/conversation/presentation/screens/'
      'direct_conversation_route_authority.dart';

  /// Production shells that may push a 1:1 conversation. The debug E2E
  /// composition root is deliberately excluded: it builds no linked authority
  /// at all, and its exclusion is documented at the construction site.
  const debugCompositionRoot = 'lib/debug/debug_e2e_composition_root.dart';
  const modalityGatePath =
      'lib/features/conversation/presentation/screens/'
      'direct_conversation_modality_gate.dart';

  List<File> productionDartFiles() {
    return Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);
  }

  /// Extracts the argument text of each `ConversationWired(` construction,
  /// balancing parentheses so nested calls do not truncate the slice.
  List<String> conversationWiredArgumentBlocks(String source) {
    final blocks = <String>[];
    const needle = 'ConversationWired(';
    var index = source.indexOf(needle);
    while (index != -1) {
      final precededByGroup =
          index >= 5 && source.substring(index - 5, index) == 'Group';
      if (!precededByGroup) {
        var depth = 0;
        var cursor = index + needle.length - 1;
        final start = cursor + 1;
        for (; cursor < source.length; cursor++) {
          final char = source[cursor];
          if (char == '(') depth++;
          if (char == ')') {
            depth--;
            if (depth == 0) break;
          }
        }
        blocks.add(source.substring(start, cursor));
      }
      index = source.indexOf(needle, index + needle.length);
    }
    return blocks;
  }

  test('TC-362-06b every production ConversationWired push carries the linked '
      'route authority', () {
    expect(
      File(authorityPath).existsSync(),
      isTrue,
      reason: 'the shared authority bundle must exist',
    );

    final offenders = <String>[];
    var productionSites = 0;

    for (final file in productionDartFiles()) {
      final path = file.path;
      if (path == wiredPath || path == debugCompositionRoot) continue;
      final source = file.readAsStringSync();
      if (!source.contains('ConversationWired(')) continue;

      for (final block in conversationWiredArgumentBlocks(source)) {
        productionSites++;
        for (final required in const <String>[
          'directEventFanout:',
          'directDeviceTrust:',
          'modalityGate:',
          'outgoingCallCapability:',
        ]) {
          if (!block.contains(required)) {
            offenders.add('$path is missing $required');
          }
        }
      }
    }

    expect(
      productionSites,
      greaterThanOrEqualTo(6),
      reason:
          'the census must actually find the production routes; a zero or '
          'near-zero count means the extractor broke, not that the tree is '
          'clean',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'a 1:1 conversation opened from ordinary navigation must reach the '
          'same linked authority the notification route has, or an '
          'initialized roster silently demotes to a single target',
    );
  });

  test(
    'TC-362-06c every shell that pushes a conversation forwards the authority '
    'it was given',
    () {
      final offenders = <String>[];

      for (final file in productionDartFiles()) {
        final path = file.path;
        if (path == wiredPath ||
            path == authorityPath ||
            path == debugCompositionRoot) {
          continue;
        }
        final source = file.readAsStringSync();
        // Use the same balanced extractor as the census above: a plain
        // substring test also matches `GroupConversationWired(`, which is a
        // different screen with no 1:1 linked authority.
        if (conversationWiredArgumentBlocks(source).isEmpty) continue;
        // A shell that pushes a conversation must own an authority to pass on,
        // either as a threaded field or (for the composition root) as a
        // locally built bundle.
        final hasField = source.contains(
          'DirectConversationRouteAuthority? directRouteAuthority',
        );
        final buildsBundle = source.contains(
          'DirectConversationRouteAuthority(',
        );
        if (!hasField && !buildsBundle) {
          offenders.add(path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'a shell that pushes a conversation without holding the authority '
            'can only pass nulls',
      );
    },
  );

  test('TC-362-06d the modality gate is resolved in exactly one place', () {
    final inlineGateBuilders = <String>[];

    for (final file in productionDartFiles()) {
      final path = file.path;
      // The bundle resolves it; the gate's own file declares the named
      // constructor being resolved.
      if (path == authorityPath || path == modalityGatePath) continue;
      final source = file.readAsStringSync();
      if (source.contains('DirectConversationModalityGate.linkedBlobFree()')) {
        inlineGateBuilders.add(path);
      }
    }

    expect(
      inlineGateBuilders,
      isEmpty,
      reason:
          'the restricted-gate expression lives on the authority bundle so '
          'every route agrees by construction; a second inline copy is how '
          'the routes diverged in the first place',
    );
  });

  test('TC-362-06e route authority resolves the current fanout, trust, and '
      'runtime modality values', () {
    final firstFanout = _fanoutSentinel('peer-first');
    final secondFanout = _fanoutSentinel('peer-second');
    final trust = _TrustSentinel();
    final outgoingCallCapability = _OutgoingCallCapabilitySentinel();
    var linkedBlobFreeRuntime = false;
    var fanoutResolutionCount = 0;
    final authority = DirectConversationRouteAuthority(
      directEventFanoutResolver: () =>
          fanoutResolutionCount++ == 0 ? firstFanout : secondFanout,
      directDeviceTrust: trust,
      isLinkedBlobFreeRuntime: () => linkedBlobFreeRuntime,
      outgoingCallCapability: outgoingCallCapability,
    );

    expect(authority.resolvedDirectEventFanout, same(firstFanout));
    expect(authority.resolvedDirectEventFanout, same(secondFanout));
    expect(
      fanoutResolutionCount,
      2,
      reason: 'identity-scoped authoring authority must not be cached',
    );
    expect(authority.resolvedDirectDeviceTrust, same(trust));
    expect(
      authority.resolvedOutgoingCallCapability,
      same(outgoingCallCapability),
    );

    final primaryGate = authority.resolvedModalityGate;
    expect(primaryGate.allowsMediaAuthoring, isTrue);
    expect(primaryGate.allowsVoiceAuthoring, isTrue);
    expect(primaryGate.allowsPrivateModes, isTrue);

    linkedBlobFreeRuntime = true;
    final linkedGate = authority.resolvedModalityGate;
    final fullLinkedMediaAuthoring =
        kDirectLinkedMediaFanoutEnabled &&
        kDirectMediaBlobCustodyClientEnabled &&
        kDirectLinkedEventFanoutEnabled;
    expect(linkedGate.allowsMediaAuthoring, fullLinkedMediaAuthoring);
    expect(linkedGate.allowsVoiceAuthoring, fullLinkedMediaAuthoring);
    expect(linkedGate.allowsPrivateModes, fullLinkedMediaAuthoring);

    DirectConversationRouteAuthority? absent;
    expect(absent.resolvedDirectEventFanout, isNull);
    expect(absent.resolvedDirectDeviceTrust, isNull);
    expect(absent.resolvedOutgoingCallCapability, isNull);
    expect(absent.resolvedModalityGate.allowsMediaAuthoring, isTrue);
  });

  test(
    'TC-362-06f Orbit consumes trust from the route bundle for contact and QR '
    'paths',
    () {
      final source = File(
        'lib/features/orbit/presentation/screens/orbit_wired.dart',
      ).readAsStringSync();

      expect(
        'widget.directRouteAuthority.resolvedDirectDeviceTrust'.allMatches(
          source,
        ),
        hasLength(greaterThanOrEqualTo(2)),
        reason:
            'both the contact-profile trust path and QR staging path must '
            'consume the same bundle threaded by StartupRouter and Feed',
      );
      expect(
        source,
        isNot(contains('widget.directDeviceTrust')),
        reason:
            'the removed standalone nullable field made the normal route '
            'bundle inert',
      );
    },
  );

  test('TC-362-06h Feed inline direct composer consumes blob-free fanout '
      'authority', () {
    final source = File(
      'lib/features/feed/presentation/screens/feed_wired.dart',
    ).readAsStringSync();
    const composerMethod = 'Future<bool> _sendContactComposerReply(';
    final methodStart = source.indexOf(composerMethod);
    expect(methodStart, greaterThanOrEqualTo(0));
    final nextMethod = source.indexOf('\n  Future<', methodStart + 1);
    final methodSource = source.substring(
      methodStart,
      nextMethod == -1 ? source.length : nextMethod,
    );

    expect(methodSource, contains('sendChatMessage('));
    expect(
      methodSource,
      contains(
        'directEventFanout:\n'
        '            widget.directRouteAuthority.resolvedDirectEventFanout',
      ),
      reason:
          'the feed composer is a direct text producer in its own right; '
          'routing the later ConversationWired push cannot authorize it',
    );
  });
}

final class _OutgoingCallCapabilitySentinel implements OutgoingCallCapability {
  @override
  bool get isOutgoingCallAvailable => true;

  @override
  Stream<bool> get outgoingCallAvailabilityChanges =>
      const Stream<bool>.empty();

  @override
  Future<bool> isOutgoingCallAvailableFor(String contactAccountPeerId) async =>
      true;

  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String contactAccountPeerId,
  ) async => OutgoingCallStartResult.started;
}

DirectEventFanoutAuthoring _fanoutSentinel(String senderTransportPeerId) {
  Never unreachable() => throw StateError('sentinel delegates are unreachable');

  return DirectEventFanoutAuthoring(
    selector: const DirectLinkedEventFanoutSelector.enabled(),
    linkedOrigin: false,
    senderTransportPeerId: senderTransportPeerId,
    readSnapshot: (_) async => unreachable(),
    encrypt: ({required recipientMlKemPublicKey, required plaintext}) async =>
        unreachable(),
    loadTextSiblings: (_) async => unreachable(),
    stageTextFanout:
        ({
          required stagedRow,
          required messageId,
          required contactAccountPeerId,
          required senderTransportPeerId,
          required expectedSnapshot,
          required candidates,
        }) async => unreachable(),
    loadEventSiblings: (_) async => unreachable(),
    stageMutationFanout:
        ({
          required expectedRow,
          required stagedRow,
          required kind,
          required eventId,
          required parentMessageId,
          required contactAccountPeerId,
          required senderTransportPeerId,
          required expectedSnapshot,
          required candidates,
        }) async => unreachable(),
    stageReactionFanout:
        ({
          required reactionRow,
          required action,
          required parentMessageId,
          required contactAccountPeerId,
          required senderTransportPeerId,
          required expectedSnapshot,
          required candidates,
        }) async => unreachable(),
  );
}

class _TrustSentinel implements DirectContactDeviceTrustCapability {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('trust sentinel must only be identity-compared');
}
