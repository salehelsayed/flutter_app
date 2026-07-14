import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private route adapter is callback-only', () {
    final requestSource = File(
      'lib/features/groups/application/announcement_private_reply_request.dart',
    ).readAsStringSync();
    final policySource = File(
      'lib/features/groups/application/announcement_private_reply_policy.dart',
    ).readAsStringSync();
    final interfaceSource = File(
      'lib/features/groups/domain/repositories/group_message_repository.dart',
    ).readAsStringSync();
    final implementationSource = File(
      'lib/features/groups/domain/repositories/group_message_repository_impl.dart',
    ).readAsStringSync();
    final applicationSource = '$requestSource\n$policySource';

    final imports = RegExp(
      r"^import '([^']+)';$",
      multiLine: true,
    ).allMatches(applicationSource).map((match) => match.group(1)!).toList();
    expect(
      imports,
      everyElement(
        anyOf(<Matcher>[
          endsWith('/media_owner_lane.dart'),
          endsWith('/contact_model.dart'),
          endsWith('/contact_repository.dart'),
          endsWith('/media_attachment.dart'),
          endsWith('/media_attachment_repository.dart'),
          endsWith('/group_member.dart'),
          endsWith('/group_message.dart'),
          endsWith('/group_model.dart'),
          endsWith('/group_message_repository.dart'),
          endsWith('/group_repository.dart'),
          endsWith('/identity_repository.dart'),
          equals('announcement_private_reply_request.dart'),
        ]),
      ),
    );

    for (final forbiddenImport in <String>[
      "dart:convert",
      "dart:io",
      "package:flutter/",
      "/presentation/",
      "/navigation/",
      "/database/",
      "/bridge/",
      "/p2p/",
      "/relay/",
      "/send_",
      "/upload_",
      "/forward_",
    ]) {
      expect(imports.join('\n'), isNot(contains(forbiddenImport)));
    }

    for (final forbiddenIdentifier in <String>[
      'BuildContext',
      'Navigator',
      'jsonEncode',
      'jsonDecode',
      'toJson',
      'fromJson',
      'toMap',
      'fromMap',
      'sendChatMessage',
      'sendGroupMessage',
      'uploadMedia',
      'ForwardCoordinator',
      'P2PService',
      'Bridge',
      'openConversation',
      'pushNamed',
      'showDialog',
    ]) {
      expect(
        RegExp('\\b$forbiddenIdentifier\\b').hasMatch(applicationSource),
        isFalse,
        reason: forbiddenIdentifier,
      );
    }
    expect(applicationSource, contains('hasCompleteOpener'));
    expect(applicationSource, isNot(contains('void Function(')));
    expect(applicationSource, isNot(contains('Future<void> Function(')));
    expect(applicationSource, isNot(contains('.call(')));
    expect(
      RegExp(
        r'\.(?:save\w*|update\w*|delete\w*|remove\w*|addContact|'
        r'archive\w*|unarchive\w*|mark\w*|send\w*|upload\w*|forward\w*)\s*\(',
      ).hasMatch(applicationSource),
      isFalse,
      reason: 'the qualification boundary must remain repository-read-only',
    );

    final requestFields = _instanceFinalFieldNames(requestSource);
    expect(requestFields, hasLength(2));
    expect(requestFields, <String>['sourceMessageId', 'senderPeerId']);

    final resolutionSource = RegExp(
      r'final class AnnouncementPrivateReplyResolution \{[\s\S]*?\n\}'
      r'\n\n/// Pure qualification',
    ).firstMatch(policySource)?.group(0);
    expect(resolutionSource, isNotNull);
    final resolutionConstructorNames = RegExp(
      r'(?:const|factory)\s+AnnouncementPrivateReplyResolution'
      r'(?:\.([A-Za-z_][A-Za-z0-9_]*))?\s*\(',
    ).allMatches(resolutionSource!).map((match) => match.group(1)).toList();
    expect(resolutionConstructorNames, contains('_available'));
    expect(resolutionConstructorNames, contains('_unavailable'));
    expect(
      resolutionConstructorNames,
      everyElement(allOf(isNotNull, startsWith('_'))),
      reason: 'every result constructor, including success, is library-private',
    );
    expect(
      RegExp(
        r'static\s+AnnouncementPrivateReplyResolution\s+'
        r'(?:available|success)\s*\(',
      ).hasMatch(resolutionSource),
      isFalse,
      reason: 'no public static success minter may bypass the resolver',
    );

    final capability = RegExp(
      r'enum GroupMessageLocalDeletionState \{[^\n]+\}\n'
      r'[\s\S]*?abstract class GroupMessageLocalDeletionAuthority \{[\s\S]*?\n\}',
    ).firstMatch(interfaceSource)?.group(0);
    expect(capability, isNotNull);
    expect(capability, contains('knownClear'));
    expect(capability, contains('deleted'));
    expect(capability, contains('unknown'));
    expect(capability, contains('Future<GroupMessageLocalDeletionState>'));
    expect(capability, isNot(contains('save')));
    expect(capability, isNot(contains('deleteMessage(')));
    expect(capability, isNot(contains('db')));

    final implementationMethod = RegExp(
      r'Future<GroupMessageLocalDeletionState> '
      r'getGroupMessageLocalDeletionState\([\s\S]*?\n  \}',
    ).firstMatch(implementationSource)?.group(0);
    expect(implementationMethod, isNotNull);
    expect(implementationMethod, contains('dbLoadGroupMessageLocalDeletionFn'));
    expect(
      implementationMethod,
      contains('GroupMessageLocalDeletionState.unknown'),
    );
    expect(
      implementationMethod,
      contains('GroupMessageLocalDeletionState.knownClear'),
    );
    expect(
      implementationMethod,
      contains('GroupMessageLocalDeletionState.deleted'),
    );
    expect(implementationMethod, isNot(contains('getLocalDeletionGroupId')));
    expect(implementationMethod, isNot(contains('dbInsert')));
    expect(implementationMethod, isNot(contains('dbDelete')));
    expect(implementationMethod, isNot(contains('dbUpdate')));
  });
}

List<String> _instanceFinalFieldNames(String source) {
  final declarations = RegExp(
    r'^  (?:late\s+)?final\s+([^;\n]+);\s*$',
    multiLine: true,
  ).allMatches(source);
  return declarations
      .map((match) {
        final declaration = match.group(1)!.split('=').first.trim();
        if (declaration.contains(',')) {
          return '<multiple-instance-fields>';
        }
        return RegExp(
              r'([A-Za-z_][A-Za-z0-9_]*)$',
            ).firstMatch(declaration)?.group(1) ??
            '<unparsed-instance-field>';
      })
      .toList(growable: false);
}
