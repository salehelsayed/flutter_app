import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

typedef GroupEngagementFrameObservation = ({Object binding, VoidCallback onVisible});

/// Reports one visible frame for an eligible content item in the current route.
///
/// The caller excludes own posts, system rows and locked placeholders with
/// [eligible], and changes [key] when the item or observation binding changes.
/// This widget does not establish group/week/consent qualification.
class GroupEngagementVisibilityProbe extends StatefulWidget {
  const GroupEngagementVisibilityProbe({
    required Key key,
    required this.eligible,
    this.onVisible,
    this.frameObservation,
    required this.child,
  }) : assert(onVisible != null || frameObservation != null),
       super(key: key);

  final bool eligible;
  final VoidCallback? onVisible;

  /// Captures the owner of the frame being painted, before async completion.
  /// Keep the provider stable; a null snapshot disables observation. A binding
  /// change requires a fresh painted frame even without a widget rebuild.
  final GroupEngagementFrameObservation? Function()? frameObservation;
  final Widget child;

  @override
  State<GroupEngagementVisibilityProbe> createState() => _ProbeState();
}

class _ProbeState extends State<GroupEngagementVisibilityProbe>
    with WidgetsBindingObserver {
  ModalRoute<dynamic>? _route;
  int _generation = 0;
  bool _pending = false;
  bool _reported = false;
  Object? _frameBinding;

  bool get _enabled =>
      mounted &&
      widget.eligible &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      _route != null &&
      _route!.isCurrent &&
      _route!.isActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _cancel() {
    _generation++;
    _pending = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (!_enabled) _cancel();
  }

  @override
  void didUpdateWidget(GroupEngagementVisibilityProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eligible != widget.eligible ||
        oldWidget.onVisible != widget.onVisible ||
        oldWidget.frameObservation != widget.frameObservation) {
      _cancel();
    }
    if (oldWidget.frameObservation != widget.frameObservation) {
      _frameBinding = null;
      _reported = false;
    }
    if (!widget.eligible) _reported = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _cancel();
    if (mounted) setState(() {});
  }

  GroupEngagementFrameObservation? _currentFrame() {
    try {
      return widget.frameObservation?.call();
    } on Object {
      return null;
    }
  }

  void _painted(_VisibilityRenderBox box) {
    final frame = _currentFrame();
    if (widget.frameObservation != null) {
      if (frame == null) {
        _cancel();
        _frameBinding = null;
        _reported = false;
        return;
      }
      if (_frameBinding != frame.binding) {
        _cancel();
        _frameBinding = frame.binding;
        _reported = false;
      }
    }
    if (_reported || _pending || !_enabled || !box.visibleInViewport) return;
    _pending = true;
    final generation = _generation;
    // The first callback belongs to the frame that painted the item. Wait for
    // its completion before confirming in the next frame, with fresh fences.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _generation) return;
        _pending = false;
        if (_reported || !_enabled || !box.visibleInViewport) return;
        if (widget.frameObservation != null &&
            _currentFrame()?.binding != frame?.binding) {
          _cancel();
          _reported = false;
          box.markNeedsPaint();
          WidgetsBinding.instance.scheduleFrame();
          return;
        }
        _reported = true;
        try {
          (frame?.onVisible ?? widget.onVisible)?.call();
        } on Object {
          // Observation must not interrupt the content item's UI lifecycle.
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _PaintProbe(onPaint: _painted, child: widget.child);
}

class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({required this.onPaint, required super.child});

  final void Function(_VisibilityRenderBox) onPaint;

  @override
  _VisibilityRenderBox createRenderObject(BuildContext context) =>
      _VisibilityRenderBox(onPaint);

  @override
  void updateRenderObject(BuildContext context, _VisibilityRenderBox box) {
    box.onPaint = onPaint;
    box.markNeedsPaint();
  }
}

class _VisibilityRenderBox extends RenderProxyBox {
  _VisibilityRenderBox(this.onPaint);

  void Function(_VisibilityRenderBox) onPaint;

  bool get visibleInViewport {
    if (!attached || !hasSize || size.isEmpty) return false;
    var visible = MatrixUtils.transformRect(getTransformTo(null), paintBounds);
    if (!visible.isFinite || visible.isEmpty) return false;
    RenderObject child = this;
    for (var ancestor = parent; ancestor != null; ancestor = ancestor.parent) {
      if (!ancestor.attached || !ancestor.paintsChild(child)) return false;
      final clip = ancestor.describeApproximatePaintClip(child);
      if (clip != null) {
        final globalClip = MatrixUtils.transformRect(
          ancestor.getTransformTo(null),
          clip,
        );
        if (!globalClip.isFinite) return false;
        visible = visible.intersect(globalClip);
      }
      if (ancestor is RenderView) {
        visible = visible.intersect(Offset.zero & ancestor.size);
      }
      if (visible.isEmpty) return false;
      child = ancestor;
    }
    return true;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint(this);
  }
}
