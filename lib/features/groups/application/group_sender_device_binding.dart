import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

class GroupSenderDeviceBinding {
  const GroupSenderDeviceBinding({
    this.deviceId,
    this.transportPeerId,
    this.devicePublicKey,
    this.keyPackageId,
  });

  final String? deviceId;
  final String? transportPeerId;
  final String? devicePublicKey;
  final String? keyPackageId;

  bool get hasDevice => deviceId != null && deviceId!.isNotEmpty;
}

Future<GroupSenderDeviceBinding> resolveGroupSenderDeviceBinding({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderPeerId,
  String? preferredDeviceId,
  String? preferredTransportPeerId,
  String? senderPublicKey,
}) async {
  final member = await groupRepo.getMember(groupId, senderPeerId);
  return resolveGroupSenderDeviceBindingFromMember(
    member: member,
    preferredDeviceId: preferredDeviceId,
    preferredTransportPeerId: preferredTransportPeerId,
    senderPublicKey: senderPublicKey,
  );
}

GroupSenderDeviceBinding resolveGroupSenderDeviceBindingFromMember({
  required GroupMember? member,
  String? preferredDeviceId,
  String? preferredTransportPeerId,
  String? senderPublicKey,
}) {
  if (member == null || member.devices.isEmpty) {
    return const GroupSenderDeviceBinding();
  }

  final device = _resolveDevice(
    member: member,
    preferredDeviceId: preferredDeviceId,
    preferredTransportPeerId: preferredTransportPeerId,
    senderPublicKey: senderPublicKey,
  );
  if (device == null) {
    return const GroupSenderDeviceBinding();
  }

  return GroupSenderDeviceBinding(
    deviceId: device.deviceId,
    transportPeerId: device.transportPeerId,
    devicePublicKey: device.deviceSigningPublicKey,
    keyPackageId: device.keyPackageId,
  );
}

GroupMemberDeviceIdentity? _resolveDevice({
  required GroupMember member,
  String? preferredDeviceId,
  String? preferredTransportPeerId,
  String? senderPublicKey,
}) {
  final byDeviceId = member.findDeviceById(preferredDeviceId);
  if (byDeviceId != null) return byDeviceId;

  final byTransport = member.findDeviceByTransportPeerId(
    preferredTransportPeerId,
  );
  if (byTransport != null) return byTransport;

  final bySigningKey = member.firstActiveDeviceForSigningKey(senderPublicKey);
  if (bySigningKey != null) return bySigningKey;

  final activeDevices = member.activeDevices;
  if (activeDevices.length == 1) return activeDevices.single;

  return null;
}
