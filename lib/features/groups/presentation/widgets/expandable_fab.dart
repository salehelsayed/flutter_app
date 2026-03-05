import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_app/features/groups/presentation/widgets/glow_fab.dart';

/// A single menu item for [ExpandableFab].
class ExpandableFabItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const ExpandableFabItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

/// Where the FAB is anchored on screen.
enum ExpandableFabAnchor { bottomRight, topRight }

/// Speed dial FAB that expands a vertical column of pill-shaped menu items.
///
/// Must be placed inside a [Stack] (not as `Scaffold.floatingActionButton`),
/// because it renders its own scrim overlay.
class ExpandableFab extends StatefulWidget {
  final List<ExpandableFabItem> items;
  final ExpandableFabAnchor anchor;
  final double fabSize;
  final EdgeInsets? safeAreaPadding;

  const ExpandableFab({
    super.key,
    required this.items,
    this.anchor = ExpandableFabAnchor.bottomRight,
    this.fabSize = 56,
    this.safeAreaPadding,
  });

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _close() {
    if (!_isOpen) return;
    setState(() {
      _isOpen = false;
      _controller.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTopRight = widget.anchor == ExpandableFabAnchor.topRight;

    final fab = GlowFab(
      size: widget.fabSize,
      onPressed: _toggle,
      icon: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.rotate(
            angle: _controller.value * math.pi / 4,
            child: child,
          );
        },
        child: Icon(
          _isOpen ? Icons.close : Icons.add,
          color: Colors.white,
          size: 28,
        ),
      ),
    );

    final menuItems = _isOpen
        ? widget.items.map((item) => _buildMenuItem(item)).toList()
        : <Widget>[];

    final children = isTopRight
        ? [
            fab,
            if (menuItems.isNotEmpty) const SizedBox(height: 12),
            ...menuItems,
          ]
        : [
            ...menuItems,
            const SizedBox(height: 12),
            fab,
          ];

    final positioned = isTopRight
        ? Positioned(
            top: (widget.safeAreaPadding?.top ?? 0) + 8,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: children,
            ),
          )
        : Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: children,
            ),
          );

    return Stack(
      children: [
        // Scrim
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              key: const Key('expandable_fab_scrim'),
              onTap: _close,
              child: ColoredBox(
                color: Colors.black.withOpacity(0.4),
              ),
            ),
          ),
        // FAB + menu
        positioned,
      ],
    );
  }

  Widget _buildMenuItem(ExpandableFabItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          item.onTap();
          _close();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                item.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
