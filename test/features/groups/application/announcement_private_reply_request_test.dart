import 'dart:io';

import 'package:flutter_app/features/groups/application/announcement_private_reply_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private route request is minimum local and non-serializable', () {
    const request = AnnouncementPrivateReplyRequest(
      sourceMessageId: 'source-message-sentinel',
      senderPeerId: 'sender-peer-sentinel',
    );
    const same = AnnouncementPrivateReplyRequest(
      sourceMessageId: 'source-message-sentinel',
      senderPeerId: 'sender-peer-sentinel',
    );
    const differentSource = AnnouncementPrivateReplyRequest(
      sourceMessageId: 'different-source',
      senderPeerId: 'sender-peer-sentinel',
    );
    const differentSender = AnnouncementPrivateReplyRequest(
      sourceMessageId: 'source-message-sentinel',
      senderPeerId: 'different-sender',
    );

    expect(request.sourceMessageId, 'source-message-sentinel');
    expect(request.senderPeerId, 'sender-peer-sentinel');
    expect(request, same);
    expect(request.hashCode, same.hashCode);
    expect(request, isNot(differentSource));
    expect(request, isNot(differentSender));

    final source = File(
      'lib/features/groups/application/announcement_private_reply_request.dart',
    ).readAsStringSync();
    final declaredFields = _instanceFinalFieldNames(source);

    expect(declaredFields, hasLength(2));
    expect(declaredFields, <String>['sourceMessageId', 'senderPeerId']);
    for (final forbidden in <String>[
      'groupId',
      'groupTitle',
      'attachmentId',
      'localPath',
      'bytes',
      'caption',
      'initialText',
      'senderDisplay',
      'quotedMessage',
      'encryptionKey',
      'nonce',
      'isForwarded',
      'diagnostic',
      'toJson',
      'fromJson',
      'toMap',
      'fromMap',
      'jsonEncode',
      'jsonDecode',
      'payload',
      'persist',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
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
