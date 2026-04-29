import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

class GroupAvatar extends StatefulWidget {
  final String groupId;
  final String name;
  final String? avatarPath;
  final Uint8List? avatarBytes;
  final double size;
  final BorderRadius borderRadius;
  final String? cacheBustKey;

  const GroupAvatar({
    super.key,
    required this.groupId,
    required this.name,
    this.avatarPath,
    this.avatarBytes,
    this.size = 48,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.cacheBustKey,
  });

  @override
  State<GroupAvatar> createState() => _GroupAvatarState();
}

class _GroupAvatarState extends State<GroupAvatar> {
  String? _resolvedPath;

  @override
  void initState() {
    super.initState();
    _resolveAvatarPath();
  }

  @override
  void didUpdateWidget(covariant GroupAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarPath != widget.avatarPath) {
      _resolveAvatarPath();
    }
  }

  Future<void> _resolveAvatarPath() async {
    final storedPath = widget.avatarPath;
    if (storedPath == null || storedPath.isEmpty) {
      if (!mounted) return;
      setState(() => _resolvedPath = null);
      return;
    }

    final candidate = p.isAbsolute(storedPath)
        ? storedPath
        : _joinDocumentsPath(storedPath);
    if (candidate == null) {
      if (!mounted) return;
      setState(() => _resolvedPath = null);
      return;
    }

    final exists = await File(candidate).exists();
    if (!mounted) return;
    setState(() => _resolvedPath = exists ? candidate : null);
  }

  String? _joinDocumentsPath(String storedPath) {
    final docsDir = UserAvatar.documentsDir;
    if (docsDir == null || docsDir.isEmpty) {
      return null;
    }
    return '$docsDir/$storedPath';
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final avatarBytes = widget.avatarBytes;
    final imagePath = _resolvedPath;
    final imageKey = widget.cacheBustKey == null || widget.cacheBustKey!.isEmpty
        ? 'group-avatar-image-${widget.groupId}'
        : 'group-avatar-image-${widget.groupId}-${widget.cacheBustKey}';
    final memoryKey =
        widget.cacheBustKey == null || widget.cacheBustKey!.isEmpty
        ? 'group-avatar-image-${widget.groupId}-memory'
        : 'group-avatar-image-${widget.groupId}-memory-${widget.cacheBustKey}';

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        color: readableColors.surfaceSubtle,
        border: Border.all(color: readableColors.divider, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: switch ((avatarBytes, imagePath)) {
          (final Uint8List bytes, _) => Image.memory(
            bytes,
            key: ValueKey(memoryKey),
            fit: BoxFit.cover,
            width: widget.size,
            height: widget.size,
            errorBuilder: _errorBuilder,
          ),
          (_, final String path) => Image.file(
            File(path),
            key: ValueKey(imageKey),
            fit: BoxFit.cover,
            width: widget.size,
            height: widget.size,
            errorBuilder: _errorBuilder,
          ),
          _ => _buildFallback(readableColors),
        },
      ),
    );
  }

  Widget _errorBuilder(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return _buildFallback(context.backgroundReadableColors);
  }

  Widget _buildFallback(BackgroundReadableColors readableColors) {
    return Container(
      key: ValueKey('group-avatar-fallback-${widget.groupId}'),
      alignment: Alignment.center,
      color: readableColors.surfaceRaised,
      child: Text(
        _initials(widget.name),
        style: TextStyle(
          fontSize: widget.size * 0.32,
          fontWeight: FontWeight.w700,
          color: readableColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';

    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    return '${words[0].substring(0, 1)}${words[1].substring(0, 1)}'
        .toUpperCase();
  }
}
