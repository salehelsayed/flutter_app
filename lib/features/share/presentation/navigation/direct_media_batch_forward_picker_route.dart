import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/share/application/direct_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart';

Route<DirectMediaBatchForwardCompletion>
buildDirectMediaBatchForwardPickerRoute({
  required DirectMediaLibraryBatchForwardDraft draft,
  required String sourceContactPeerId,
  required ContactRepository contactRepository,
  required DirectMediaBatchForwardDeliveryCoordinator deliveryCoordinator,
}) => MaterialPageRoute<DirectMediaBatchForwardCompletion>(
  builder: (_) => DirectMediaBatchForwardPickerWired(
    draft: draft,
    sourceContactPeerId: sourceContactPeerId,
    contactRepository: contactRepository,
    deliveryCoordinator: deliveryCoordinator,
  ),
);
