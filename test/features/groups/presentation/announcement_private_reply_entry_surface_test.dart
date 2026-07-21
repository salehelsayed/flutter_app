import 'dart:io';

import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    setGroupExitIntentAccessSinks(
      forGroup: (_) async => null,
      all: () async => const <GroupExitIntent>[],
    );
  });
  tearDown(setGroupExitIntentAccessSinks);

  test(
    'five group entry sites wire one complete or explicit null opener contract',
    () {
      const mainPath = 'lib/main.dart';
      const feedPath = 'lib/features/feed/presentation/screens/feed_wired.dart';
      const orbitPath =
          'lib/features/orbit/presentation/screens/orbit_wired.dart';
      const listPath =
          'lib/features/groups/presentation/screens/group_list_wired.dart';
      const pickerPath =
          'lib/features/groups/presentation/screens/create_group_picker_wired.dart';
      const sites = <String>[
        mainPath,
        feedPath,
        orbitPath,
        listPath,
        pickerPath,
      ];
      final sources = <String, String>{
        for (final path in sites) path: File(path).readAsStringSync(),
      };
      final constructors = <String, String>{};
      for (final path in sites) {
        final blocks = _extractInvocations(
          sources[path]!,
          'GroupConversationWired',
        );
        expect(
          blocks,
          hasLength(1),
          reason: '$path must own exactly one current group constructor',
        );
        constructors[path] = blocks.single;
      }
      expect(constructors, hasLength(5));

      expect(
        constructors[mainPath],
        contains(
          'openAnnouncementSenderConversation: (contact) =>\n'
          '                  _openConversationForContact(',
        ),
      );
      expect(constructors[mainPath], contains('navigator: navigator'));
      expect(constructors[mainPath], contains('contact: contact'));
      expect(
        constructors[feedPath],
        contains(
          'openAnnouncementSenderConversation: _openConversationForContact',
        ),
      );
      expect(
        constructors[orbitPath],
        contains(
          'openAnnouncementSenderConversation: _openConversationForContact',
        ),
      );
      expect(
        constructors[listPath],
        contains('openAnnouncementSenderConversation: null'),
      );
      expect(
        constructors[pickerPath],
        contains(
          'openAnnouncementSenderConversation:\n'
          '                widget.openAnnouncementSenderConversation',
        ),
      );

      final pickerSource = sources[pickerPath]!;
      expect(
        pickerSource,
        contains(
          'final OpenAnnouncementSenderConversation? '
          'openAnnouncementSenderConversation;',
        ),
      );

      for (final entry in <(String, String)>[
        (mainPath, 'Future<void> _openConversationForContact({'),
        (feedPath, 'Future<void> _openConversationForContact('),
        (orbitPath, 'Future<void> _openConversationForContact('),
      ]) {
        final (path, signature) = entry;
        final opener = _extractFunction(sources[path]!, signature);
        expect(
          opener.trimLeft(),
          startsWith('Future<void> _openConversationForContact'),
          reason: '$path opener must preserve the awaited Future contract',
        );
        expect(opener, contains('buildConversationRoute('), reason: path);
        final directBuilders = _extractInvocations(opener, 'ConversationWired');
        expect(
          directBuilders,
          hasLength(1),
          reason: '$path opener must reuse one complete direct builder',
        );
        final directBuilder = directBuilders.single;
        for (final requiredDependency in <String>[
          'contact: contact',
          'identityRepo:',
          'messageRepo:',
          'chatMessageListener:',
          'p2pService:',
        ]) {
          expect(directBuilder, contains(requiredDependency), reason: path);
        }
        final awaitsRouteReturn = RegExp(
          r'await\s+(?:navigator\.push|Navigator\.of\(context\)\.push|pushedRoute)',
        ).hasMatch(opener);
        expect(
          awaitsRouteReturn,
          isTrue,
          reason: '$path opener must await the existing route through pop',
        );
        final forbiddenSeeds = <String>[
          'initialMessages:',
          'initialAttachments:',
          'initialPendingMedia:',
          'quotedMessageId:',
          'sourceMessageId:',
          'senderPeerId:',
          'groupId:',
          'caption:',
          'isForwarded:',
          'encryptionKey',
          'encryptionNonce',
          'wireEnvelope:',
          'payload:',
        ];
        if (path == orbitPath) {
          // Plan 260's Ask-for-a-new-invite action reuses Orbit's complete
          // opener with an optional localized draft. The announcement callback
          // is still typed to one ContactModel argument, so this named value is
          // null on the announcement path and cannot seed group content.
          expect(opener, contains('String? initialText'));
          expect(directBuilder, contains('initialText: initialText'));
        } else {
          forbiddenSeeds.add('initialText:');
        }
        for (final forbiddenSeed in forbiddenSeeds) {
          expect(
            directBuilder,
            isNot(contains(forbiddenSeed)),
            reason: '$path must not seed $forbiddenSeed into the private route',
          );
        }
      }

      final orbitCreatePicker = _extractInvocations(
        sources[orbitPath]!,
        'CreateGroupPickerWired',
      );
      expect(orbitCreatePicker, hasLength(1));
      expect(
        orbitCreatePicker.single,
        contains(
          'openAnnouncementSenderConversation: _openConversationForContact',
        ),
        reason: 'Orbit must pass its same complete opener into create-group',
      );
    },
  );

  test('group wired never constructs a partial direct conversation', () {
    final source = File(
      'lib/features/groups/presentation/screens/group_conversation_wired.dart',
    ).readAsStringSync();
    expect(source, contains('typedef OpenAnnouncementSenderConversation'));
    expect(
      source.replaceAll('GroupConversationWired(', ''),
      isNot(contains('ConversationWired(')),
    );

    final plan247Block = _extractFunction(
      source,
      'Future<MediaViewerActionResult> _dispatchAnnouncementPrivateReply(',
    );
    for (final forbidden in <String>[
      'sendChatMessage(',
      'sendGroupMessage(',
      'uploadMedia(',
      'P2PService',
      'Bridge',
      'MessageRepository',
      'ChatMessageListener',
      'initialText:',
      'quotedMessageId',
      'initialAttachments',
      'initialPendingMedia',
    ]) {
      expect(plan247Block, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}

List<String> _extractInvocations(String source, String constructorName) {
  final result = <String>[];
  final pattern = RegExp('\\b${RegExp.escape(constructorName)}\\s*\\(');
  var searchFrom = 0;
  while (true) {
    final match =
        pattern.matchAsPrefix(source, searchFrom) ??
        pattern.allMatches(source, searchFrom).firstOrNull;
    if (match == null) return result;
    final open = source.indexOf('(', match.start);
    final close = _matchingDelimiter(source, open, '(', ')');
    result.add(source.substring(match.start, close + 1));
    searchFrom = close + 1;
  }
}

String _extractFunction(String source, String signatureAnchor) {
  final start = source.indexOf(signatureAnchor);
  if (start < 0) {
    throw TestFailure('Missing function signature: $signatureAnchor');
  }
  final parameterOpen = source.indexOf('(', start);
  if (parameterOpen < 0) {
    throw TestFailure('Missing function parameters: $signatureAnchor');
  }
  final parameterClose = _matchingDelimiter(source, parameterOpen, '(', ')');
  final open = source.indexOf('{', parameterClose + 1);
  if (open < 0) {
    throw TestFailure('Missing function body: $signatureAnchor');
  }
  final close = _matchingDelimiter(source, open, '{', '}');
  return source.substring(start, close + 1);
}

int _matchingDelimiter(
  String source,
  int openIndex,
  String openDelimiter,
  String closeDelimiter,
) {
  var depth = 0;
  String? quote;
  var escaped = false;
  var lineComment = false;
  var blockComment = false;
  for (var index = openIndex; index < source.length; index++) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';
    if (lineComment) {
      if (char == '\n') lineComment = false;
      continue;
    }
    if (blockComment) {
      if (char == '*' && next == '/') {
        blockComment = false;
        index += 1;
      }
      continue;
    }
    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '/' && next == '/') {
      lineComment = true;
      index += 1;
      continue;
    }
    if (char == '/' && next == '*') {
      blockComment = true;
      index += 1;
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
      continue;
    }
    if (char == openDelimiter) {
      depth += 1;
    } else if (char == closeDelimiter) {
      depth -= 1;
      if (depth == 0) return index;
    }
  }
  throw TestFailure(
    'Unbalanced $openDelimiter$closeDelimiter from offset $openIndex',
  );
}
