import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

/// Pure UI screen for group conversation.
///
/// Displays header with group name/type, message list using letter cards,
/// and compose area. No business logic -- all data passed via props.
class GroupConversationScreen extends StatelessWidget {
  final GroupModel group;
  final List<GroupMessage> messages;
  final String? ownPeerId;
  final ValueChanged<String> onSend;
  final VoidCallback onBack;
  final VoidCallback? onInfo;
  final bool canWrite;
  final ScrollController? scrollController;
  final Map<String, List<MediaAttachment>> mediaMap;
  final List<File> pendingAttachments;
  final bool isUploading;
  final bool isProcessing;
  final double processingProgress;
  final ValueChanged<int>? onRemoveAttachment;
  final VoidCallback? onAttach;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onRecordCancel;
  final bool isRecording;
  final Duration recordingDuration;
  final List<double> amplitudeValues;
  final void Function(String messageId, int index)? onMediaTap;

  const GroupConversationScreen({
    super.key,
    required this.group,
    required this.messages,
    this.ownPeerId,
    required this.onSend,
    required this.onBack,
    this.onInfo,
    this.canWrite = true,
    this.scrollController,
    this.mediaMap = const {},
    this.pendingAttachments = const [],
    this.isUploading = false,
    this.isProcessing = false,
    this.processingProgress = 0.0,
    this.onRemoveAttachment,
    this.onAttach,
    this.onRecordStart,
    this.onRecordStop,
    this.onRecordCancel,
    this.isRecording = false,
    this.recordingDuration = Duration.zero,
    this.amplitudeValues = const [],
    this.onMediaTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
      child: Column(
        children: [
          // Header
          _buildHeader(context),
          // Body
          Expanded(
            child: messages.isEmpty ? _buildEmptyState() : _buildMessageList(),
          ),
          // Attachment preview strip
          if (pendingAttachments.isNotEmpty || isProcessing)
            AttachmentPreviewStrip(
              attachments: pendingAttachments,
              isUploading: isUploading,
              isProcessing: isProcessing,
              processingProgress: processingProgress,
              onRemove: onRemoveAttachment,
            ),
          // Compose area
          if (!canWrite)
            _buildReadOnlyBanner()
          else
            ComposeArea(
              onSend: onSend,
              onAttach: onAttach,
              hasAttachments: pendingAttachments.isNotEmpty,
              isProcessing: isProcessing,
              onRecordStart: onRecordStart,
              onRecordStop: onRecordStop,
              onRecordCancel: onRecordCancel,
              isRecording: isRecording,
              recordingDuration: recordingDuration,
              amplitudeValues: amplitudeValues,
            ),
        ],
      ),
    ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.06),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              color: Colors.white,
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GroupTypeBadge(type: group.type),
                    ],
                  ),
                ],
              ),
            ),
            if (onInfo != null)
              IconButton(
                icon: Icon(
                  Icons.info_outline,
                  color: Colors.white.withOpacity(0.6),
                  size: 22,
                ),
                onPressed: onInfo,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 12),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            canWrite
                ? 'Send a message to start the conversation'
                : 'Waiting for messages',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        // Reversed list: index 0 = newest
        final message = messages[messages.length - 1 - index];
        final isSent = message.senderPeerId == ownPeerId;

        return Padding(
          key: ValueKey('grp-msg-${message.id}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: LetterCard(
            senderPeerId: message.senderPeerId,
            senderName: isSent ? 'You' : (message.senderUsername ?? 'Unknown'),
            text: message.text,
            time: _formatTime(message.timestamp),
            isIncoming: !isSent,
            status: isSent ? message.status : null,
            media: mediaMap[message.id] ?? const [],
            onMediaTap: onMediaTap != null
                ? (index) => onMediaTap!(message.id, index)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildReadOnlyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Text(
        'Only admins can send messages in this group',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withOpacity(0.35),
        ),
      ),
    );
  }

  static String _formatTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}
