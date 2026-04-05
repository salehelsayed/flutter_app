import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

enum ShareTargetSelectionKind { contact, group }

class ShareTargetSelection {
  final ShareTargetSelectionKind kind;
  final ContactModel? contact;
  final GroupModel? group;

  const ShareTargetSelection._({required this.kind, this.contact, this.group});

  factory ShareTargetSelection.contact(ContactModel contact) {
    return ShareTargetSelection._(
      kind: ShareTargetSelectionKind.contact,
      contact: contact,
    );
  }

  factory ShareTargetSelection.group(GroupModel group) {
    return ShareTargetSelection._(
      kind: ShareTargetSelectionKind.group,
      group: group,
    );
  }

  String get key => switch (kind) {
    ShareTargetSelectionKind.contact => contactKey(contact!.peerId),
    ShareTargetSelectionKind.group => groupKey(group!.id),
  };

  String get label => switch (kind) {
    ShareTargetSelectionKind.contact => contact!.username,
    ShareTargetSelectionKind.group => group!.name,
  };

  ContactModel get requireContact => contact!;

  GroupModel get requireGroup => group!;

  static String contactKey(String peerId) => 'contact:$peerId';

  static String groupKey(String groupId) => 'group:$groupId';
}
