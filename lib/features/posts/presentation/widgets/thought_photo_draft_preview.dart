import 'dart:io';

import 'package:flutter/material.dart';

/// The picked photos inside the Thought composer, drawn the way friends will
/// see them on the card: the whole photo on black. Each has an X to take it
/// out. There is no separate framing step.
class ThoughtPhotoDraftPreview extends StatelessWidget {
  const ThoughtPhotoDraftPreview({
    super.key,
    required this.paths,
    required this.onRemove,
  });

  final List<String> paths;
  final ValueChanged<int> onRemove;

  static const _height = 240.0;

  @override
  Widget build(BuildContext context) {
    final single = paths.length == 1;
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: single ? const NeverScrollableScrollPhysics() : null,
          itemCount: paths.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) => SizedBox(
            width: single ? constraints.maxWidth : _height * .75,
            child: _PhotoTile(
              key: ValueKey('thought-photo-draft-$index'),
              path: paths[index],
              removeLabel: MaterialLocalizations.of(
                context,
              ).deleteButtonTooltip,
              onRemove: () => onRemove(index),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    super.key,
    required this.path,
    required this.removeLabel,
    required this.onRemove,
  });

  final String path;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final image = FileImage(File(path));
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          Image(
            image: ResizeImage.resizeIfNeeded(1440, null, image),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, color: Colors.white54),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              key: const ValueKey('thought-photo-draft-remove'),
              tooltip: removeLabel,
              onPressed: onRemove,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x99000000),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
