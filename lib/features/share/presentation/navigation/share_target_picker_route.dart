import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';

Route<void> buildShareTargetPickerRoute({
  required ShareIntent shareIntent,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepository,
  required MessageRepository messageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required ChatMessageListener chatMessageListener,
  required Bridge bridge,
  required P2PService p2pService,
  required MediaFileManager mediaFileManager,
  required ImageProcessor imageProcessor,
  SecureKeyStore? secureKeyStore,
  ActiveConversationTracker? conversationTracker,
  AudioRecorderService? audioRecorderService,
  ReactionRepository? reactionRepository,
  ReactionListener? reactionListener,
  GroupRepository? groupRepository,
  GroupMessageRepository? groupMessageRepository,
  GroupMessageListener? groupMessageListener,
  ActiveConversationTracker? groupConversationTracker,
  IntroductionRepository? introductionRepository,
  AppShellController? appShellController,
  Future<void> Function(ShareBatchDeliveryResult? result)? onClose,
  Future<void> Function()? preSendReady,
}) {
  return MaterialPageRoute<void>(
    builder: (_) => ShareTargetPickerWired(
      shareIntent: shareIntent,
      identityRepo: identityRepo,
      contactRepository: contactRepository,
      messageRepository: messageRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      chatMessageListener: chatMessageListener,
      bridge: bridge,
      p2pService: p2pService,
      mediaFileManager: mediaFileManager,
      imageProcessor: imageProcessor,
      secureKeyStore: secureKeyStore,
      conversationTracker: conversationTracker,
      audioRecorderService: audioRecorderService,
      reactionRepository: reactionRepository,
      reactionListener: reactionListener,
      groupRepository: groupRepository,
      groupMessageRepository: groupMessageRepository,
      groupMessageListener: groupMessageListener,
      groupConversationTracker: groupConversationTracker,
      introductionRepository: introductionRepository,
      appShellController: appShellController,
      onClose: onClose,
      preSendReady: preSendReady,
    ),
  );
}
