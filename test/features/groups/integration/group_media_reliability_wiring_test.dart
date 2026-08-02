import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<String> _balancedInvocations(String source, String token) {
  final invocations = <String>[];
  var searchFrom = 0;
  while (true) {
    final tokenIndex = source.indexOf(token, searchFrom);
    if (tokenIndex < 0) break;
    final openIndex = tokenIndex + token.length - 1;
    var depth = 0;
    var quote = 0;
    var escaped = false;
    var lineComment = false;
    var blockComment = false;
    var endIndex = -1;

    for (var index = openIndex; index < source.length; index++) {
      final code = source.codeUnitAt(index);
      final next = index + 1 < source.length
          ? source.codeUnitAt(index + 1)
          : -1;

      if (lineComment) {
        if (code == 0x0a || code == 0x0d) lineComment = false;
        continue;
      }
      if (blockComment) {
        if (code == 0x2a && next == 0x2f) {
          blockComment = false;
          index++;
        }
        continue;
      }
      if (quote != 0) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == quote) {
          quote = 0;
        }
        continue;
      }
      if (code == 0x2f && next == 0x2f) {
        lineComment = true;
        index++;
        continue;
      }
      if (code == 0x2f && next == 0x2a) {
        blockComment = true;
        index++;
        continue;
      }
      if (code == 0x27 || code == 0x22) {
        quote = code;
        continue;
      }
      if (code == 0x28) {
        depth++;
      } else if (code == 0x29) {
        depth--;
        if (depth == 0) {
          endIndex = index + 1;
          break;
        }
      }
    }

    if (endIndex < 0) {
      fail('Unbalanced $token invocation at $tokenIndex');
    }
    invocations.add(source.substring(tokenIndex, endIndex));
    searchFrom = endIndex;
  }
  return invocations;
}

String _compactDart(String source) => source.replaceAll(RegExp(r'\s+'), '');

List<String> _topLevelArguments(String invocation) {
  final openIndex = invocation.indexOf('(');
  if (openIndex < 0) {
    fail('Invocation has no opening parenthesis: $invocation');
  }

  final arguments = <String>[];
  var argumentStart = openIndex + 1;
  var parentheses = 1;
  var brackets = 0;
  var braces = 0;
  var quote = 0;
  var escaped = false;
  var lineComment = false;
  var blockComment = false;

  for (var index = openIndex + 1; index < invocation.length; index++) {
    final code = invocation.codeUnitAt(index);
    final next = index + 1 < invocation.length
        ? invocation.codeUnitAt(index + 1)
        : -1;

    if (lineComment) {
      if (code == 0x0a || code == 0x0d) lineComment = false;
      continue;
    }
    if (blockComment) {
      if (code == 0x2a && next == 0x2f) {
        blockComment = false;
        index++;
      }
      continue;
    }
    if (quote != 0) {
      if (escaped) {
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == quote) {
        quote = 0;
      }
      continue;
    }
    if (code == 0x2f && next == 0x2f) {
      lineComment = true;
      index++;
      continue;
    }
    if (code == 0x2f && next == 0x2a) {
      blockComment = true;
      index++;
      continue;
    }
    if (code == 0x27 || code == 0x22) {
      quote = code;
      continue;
    }

    switch (code) {
      case 0x28:
        parentheses++;
        break;
      case 0x29:
        parentheses--;
        if (parentheses == 0) {
          final finalArgument = invocation.substring(argumentStart, index);
          if (finalArgument.trim().isNotEmpty) arguments.add(finalArgument);
          return arguments;
        }
        break;
      case 0x5b:
        brackets++;
        break;
      case 0x5d:
        brackets--;
        break;
      case 0x7b:
        braces++;
        break;
      case 0x7d:
        braces--;
        break;
      case 0x2c:
        if (parentheses == 1 && brackets == 0 && braces == 0) {
          arguments.add(invocation.substring(argumentStart, index));
          argumentStart = index + 1;
        }
        break;
    }
  }

  fail('Unbalanced invocation: $invocation');
}

List<String> _namedArgumentExpressions(String invocation, String name) {
  final prefix = '$name:';
  return _topLevelArguments(invocation)
      .map(_compactDart)
      .where((argument) => argument.startsWith(prefix))
      .map((argument) => argument.substring(prefix.length))
      .toList(growable: false);
}

void main() {
  test(
    'P269 proof accept supplies the complete device-bound recipient tuple',
    () {
      final compositionSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      final acceptInvocations = _balancedInvocations(
        compositionSource,
        'acceptPendingGroupInvite(',
      ).where((invocation) => invocation.contains('groupId: groupId'));

      expect(acceptInvocations, hasLength(1));
      final accept = _compactDart(acceptInvocations.single);
      expect(accept, contains('senderPeerId:identity.peerId'));
      expect(accept, contains('ownDeviceId:transportPeerId'));
      expect(accept, contains('ownTransportPeerId:transportPeerId'));
      expect(accept, contains('ownMlKemPublicKey:identity.mlKemPublicKey'));
      expect(
        accept,
        contains(
          'ownKeyPackageId:defaultGroupWelcomeKeyPackageIdForDevice('
          'transportPeerId,)',
        ),
      );
      expect(
        accept,
        contains('ownKeyPackagePublicMaterial:identity.mlKemPublicKey'),
      );
    },
  );

  test(
    'P269 device proof invokes the exact production periodic retry callbacks',
    () {
      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final compositionSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      final actions = _balancedInvocations(
        compositionSource,
        'runGroupMediaReliabilityE2EAction(',
      );

      expect(actions, hasLength(1));
      expect(
        productionSource,
        contains('if (debugE2EComposition?.startsIntroPoller ?? false) {'),
        reason:
            'the bootstrap must avoid constructing poller dependencies for '
            'an inactive root',
      );
      expect(
        productionSource,
        contains('debugE2EComposition!.startIntroPollerAfterColdRecovery('),
        reason: 'the bootstrap must retain the post-recovery phase handoff',
      );
      final action = _compactDart(actions.single);
      expect(
        action,
        contains('pendingMessageRetrier.retryIncompleteGroupUploadsPeriodicFn'),
      );
      expect(
        action,
        contains(
          'pendingMessageRetrier.retryIncompleteGroupDownloadsPeriodicFn',
        ),
      );
      expect(
        action,
        isNot(contains('retryIncompleteGroupUploads(')),
        reason:
            'The proof must not reconstruct production periodic upload wiring.',
      );
      expect(
        action,
        isNot(contains('groupMediaDownloadCoordinator.call')),
        reason:
            'The proof must invoke the retrier-owned periodic download closure.',
      );
    },
  );

  test(
    'P269 every production group conversation invocation shares one gated download coordinator',
    () {
      final discovered = <String, List<String>>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalizedPath = entity.path.replaceAll('\\', '/');
        final source = entity.readAsStringSync();
        final invocations = _balancedInvocations(
          source,
          'GroupConversationWired(',
        );
        if (normalizedPath.endsWith(
          '/features/groups/presentation/screens/group_conversation_wired.dart',
        )) {
          invocations.removeWhere((invocation) {
            return _compactDart(
              invocation,
            ).startsWith('GroupConversationWired({');
          });
        }
        if (invocations.isNotEmpty) {
          discovered[normalizedPath] = invocations;
        }
      }

      const expectedCoordinatorExpressionsByPath = <String, List<String>>{
        'lib/app/application_root.dart': <String>[
          'widget.groupMediaDownloadCoordinator',
        ],
        'lib/debug/debug_e2e_composition_root.dart': <String>[
          'dependencies.groupMediaDownloadCoordinator',
        ],
        'lib/features/groups/presentation/screens/create_group_picker_wired.dart':
            <String>['widget.groupMediaDownloadCoordinator'],
        'lib/features/orbit/presentation/screens/orbit_wired.dart': <String>[
          'widget.groupMediaDownloadCoordinator',
        ],
        'lib/features/feed/presentation/screens/feed_wired.dart': <String>[
          'widget.groupMediaDownloadCoordinator',
        ],
      };
      expect(
        discovered.keys.toSet(),
        expectedCoordinatorExpressionsByPath.keys.toSet(),
        reason:
            'The production baseline has four direct paths plus the isolated '
            'debug/E2E proof path. A new path must be enumerated and wired '
            'explicitly.',
      );

      for (final entry in expectedCoordinatorExpressionsByPath.entries) {
        final invocations = discovered[entry.key]!;
        expect(
          invocations,
          hasLength(entry.value.length),
          reason:
              '${entry.key} must have only its enumerated direct production '
              'and compile-gated proof paths.',
        );
        final actualExpressions = <String>[];
        for (final invocation in invocations) {
          final expressions = _namedArgumentExpressions(
            invocation,
            'groupMediaDownloadCoordinator',
          );
          expect(
            expressions,
            hasLength(1),
            reason:
                'Every ${entry.key} invocation must pass exactly one shared '
                'download coordinator.',
          );
          actualExpressions.add(expressions.single);
        }
        expect(
          actualExpressions,
          unorderedEquals(entry.value),
          reason:
              '${entry.key} must pass only the enumerated root/widget '
              'coordinator expressions; null or another instance is '
              'forbidden.',
        );
      }

      final coordinatorConstructions = <String, List<String>>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalizedPath = entity.path.replaceAll('\\', '/');
        if (normalizedPath.endsWith(
          '/features/groups/application/'
          'retry_incomplete_group_downloads_use_case.dart',
        )) {
          continue;
        }
        final source = entity.readAsStringSync();
        final invocations = <String>[
          ..._balancedInvocations(
            source,
            'RetryIncompleteGroupDownloadsUseCase(',
          ),
          ..._balancedInvocations(source, 'GroupMediaDownloadCoordinator('),
        ];
        if (invocations.isNotEmpty) {
          coordinatorConstructions[normalizedPath] = invocations;
        }
      }
      expect(
        coordinatorConstructions.keys.toSet(),
        <String>{'lib/app/bootstrap/production_application_bootstrap.dart'},
        reason:
            'Production must construct the shared group-media download '
            'coordinator in the production bootstrap only.',
      );
      expect(
        coordinatorConstructions['lib/app/bootstrap/production_application_bootstrap.dart'],
        hasLength(1),
        reason:
            'Exactly one RetryIncompleteGroupDownloadsUseCase instance may be '
            'constructed for every automatic production trigger.',
      );

      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r'\bfinal\s+groupMediaDownloadCoordinator\s*=\s*'
          r'RetryIncompleteGroupDownloadsUseCase\s*\(',
        ).allMatches(productionSource),
        hasLength(1),
        reason:
            'The singleton concrete coordinator must be bound to the exact '
            'root expression threaded through production.',
      );
      final myAppInvocations = _balancedInvocations(productionSource, 'MyApp(')
        ..removeWhere(
          (invocation) => _compactDart(invocation).startsWith('MyApp({'),
        );
      expect(myAppInvocations, hasLength(1));
      expect(
        _namedArgumentExpressions(
          myAppInvocations.single,
          'groupMediaDownloadCoordinator',
        ),
        <String>['groupMediaDownloadCoordinator'],
        reason:
            'The sole concrete coordinator must seed the production widget '
            'tree; a null or alternate root instance is forbidden.',
      );
    },
  );

  test(
    'TC-322-02 every production group-inbox drain forwards pendingReactionRepo',
    () {
      // Plan 322: `handleIncomingGroupReaction` buffers a reaction whose target
      // message has not landed ONLY when `pendingReactionRepo != null`
      // (handle_incoming_group_reaction_use_case.dart:182-202). Otherwise it
      // emits GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE and returns `unknownMessage`
      // with no persistence — and the relay entry is already consumed by the
      // drain that dropped it, so nothing ever re-delivers it.
      //
      // Five production entry points omitted the argument, including the
      // app-resume drain. This census is the fix's causal pin: a unit test can
      // only prove one wiring, and the defect IS the wiring.
      const sites = <String, String>{
        'lib/app/lifecycle/handle_app_resumed.dart': 'drainGroupOfflineInbox(',
        'lib/features/identity/presentation/startup_router.dart':
            'drainGroupOfflineInbox(',
        'lib/app/bootstrap/production_application_bootstrap.dart':
            'drainGroupOfflineInbox(',
        'lib/features/push/application/prepare_notification_route_target_use_case.dart':
            'drainGroupOfflineInboxForGroup(',
        'lib/app/application_root.dart': 'drainGroupOfflineInboxForGroup(',
        // Plan 325: this lane's ABSENCE from the census is the mechanical
        // reason plan 322 missed it. All three accept-lane drain sites funnel
        // through the single invocation in this file.
        'lib/features/groups/application/accept_pending_group_invite_use_case.dart':
            'drainGroupOfflineInboxForGroup(',
      };

      sites.forEach((path, token) {
        final source = File(path).readAsStringSync();
        final invocations = _balancedInvocations(source, token)
            // Skip the continuation/forwarding declarations — only real
            // invocations carry a `bridge:` argument.
            .where((invocation) => invocation.contains('bridge:'))
            .toList();

        expect(
          invocations,
          isNotEmpty,
          reason: '$path no longer invokes $token — re-derive this census',
        );

        for (final invocation in invocations) {
          expect(
            _compactDart(invocation),
            contains('pendingReactionRepo:'),
            reason:
                '$path invokes $token without pendingReactionRepo — a drained '
                'reaction whose target has not arrived would be dropped '
                'permanently on that lane',
          );
        }
      });
    },
  );

  test(
    'TC-325-04 every acceptPendingGroupInvite caller supplies a listener',
    () {
      // Plan 325 forwards the pending-reaction repo off the listener
      // (`groupMessageListener?.pendingReactionRepository`). That makes
      // correctness depend on the listener actually being supplied — and
      // acceptPendingGroupInvite's parameter is NULLABLE
      // (accept_pending_group_invite_use_case.dart:61). A caller that omits it
      // silently reopens the drop, and the per-call-site token census stays
      // GREEN because the argument text is still present at the drain site.
      // This is the row that closes that hole.
      const callerPaths = <String>[
        'lib/features/orbit/presentation/screens/orbit_wired.dart',
        'lib/debug/debug_e2e_composition_root.dart',
      ];

      for (final path in callerPaths) {
        final source = File(path).readAsStringSync();
        final invocations = _balancedInvocations(
          source,
          'acceptPendingGroupInvite(',
        ).where((invocation) => invocation.contains('groupId:')).toList();

        expect(
          invocations,
          isNotEmpty,
          reason: '$path no longer calls acceptPendingGroupInvite — re-derive '
              'this census',
        );

        for (final invocation in invocations) {
          expect(
            _compactDart(invocation),
            contains('groupMessageListener:'),
            reason:
                '$path calls acceptPendingGroupInvite without a listener, so '
                'the accept lane would drain with a null pending-reaction '
                'buffer and drop target-absent reactions permanently',
          );
        }
      }
    },
  );

  test(
    'TC-322-02b the restarted startup router forwards the pending-reaction repo',
    () {
      // `_buildRestartedStartupRouter` hand-forwards 60+ fields. Omitting one is
      // silent — the field is nullable, so the analyzer stays quiet and the
      // account-migration restart path would drain with a null buffer.
      final source = File(
        'lib/features/identity/presentation/startup_router.dart',
      ).readAsStringSync();
      final rebuilds = _balancedInvocations(source, 'StartupRouter(')
          .where((invocation) => invocation.contains('groupRepository:'))
          .toList();

      expect(rebuilds, isNotEmpty);
      for (final rebuild in rebuilds) {
        expect(
          _compactDart(rebuild),
          contains('groupPendingReactionRepository:'),
          reason:
              'the restarted StartupRouter drops the pending-reaction repo, so '
              'post-migration drains would silently discard buffered reactions',
        );
      }
    },
  );
}
