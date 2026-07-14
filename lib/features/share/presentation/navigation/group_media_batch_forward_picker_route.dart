import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/share/application/group_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/features/share/presentation/screens/group_media_batch_forward_picker_wired.dart';

Route<GroupMediaBatchForwardCompletion> buildGroupMediaBatchForwardPickerRoute({
  required GroupMediaBatchForwardDraft draft,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required GroupRepository groupRepository,
  required GroupMediaBatchForwardDeliveryCoordinator deliveryCoordinator,
}) => MaterialPageRoute<GroupMediaBatchForwardCompletion>(
  builder: (_) => GroupMediaBatchForwardPickerWired(
    draft: draft,
    identityRepository: identityRepository,
    contactRepository: contactRepository,
    groupRepository: groupRepository,
    deliveryCoordinator: deliveryCoordinator,
  ),
);
