import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the actual node updates before the engine receives them.
class IosSemanticsRecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  final _updates = <List<_NodeUpdate>>[];

  void clearSemanticsUpdates() => _updates.clear();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingBuilder(super.createSemanticsUpdateBuilder(), _updates.add);

  /// Replays successive batches in capture order. The native batch is unordered,
  /// so each batch can also be applied in reverse node order.
  Map<int, Rect> replayIosFrames(double dpr, {bool reverseNodeOrder = false}) {
    final objects = _replayIos(_updates, reverseNodeOrder: reverseNodeOrder);
    return {
      for (final entry in objects.entries)
        entry.key: _iosFrame(entry.value, dpr),
    };
  }
}

class _NodeUpdate {
  _NodeUpdate(this.id, this.rect, this.transform, this.children, this.hit);
  final int id;
  final Rect rect;
  final Float64List transform;
  final List<int> children;
  final List<int> hit;
}

class _RecordingBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingBuilder(this._real, this._record);
  final ui.SemanticsUpdateBuilder _real;
  final void Function(List<_NodeUpdate>) _record;
  final _nodes = <_NodeUpdate>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    if (invocation.memberName == #updateNode) {
      _nodes.add(
        _NodeUpdate(
          args[#id] as int,
          args[#rect] as Rect,
          Float64List.fromList(args[#transform] as Float64List),
          List<int>.of(args[#childrenInTraversalOrder] as Int32List),
          List<int>.of(args[#childrenInHitTestOrder] as Int32List),
        ),
      );
      return Function.apply(_real.updateNode, const [], args);
    }
    if (invocation.memberName == #build) {
      _record(List.of(_nodes));
      return _real.build();
    }
    return super.noSuchMethod(invocation);
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => _real.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );
}

class _IosObject {
  _IosObject(this.node);
  _NodeUpdate node;
  _IosObject? parent;
  List<_IosObject> children = [];
  List<_IosObject> hit = [];
}

/// Mirrors iOS accessibility_bridge.mm UpdateSemantics and SemanticsObject.mm
/// setChildren, setChildrenInHitTestOrder, and dealloc.
Map<int, _IosObject> _replayIos(
  List<List<_NodeUpdate>> updates, {
  required bool reverseNodeOrder,
}) {
  final objects = <int, _IosObject>{};
  for (final update in updates) {
    final byId = {for (final n in update) n.id: n};
    _IosObject get(int id) =>
        objects.putIfAbsent(id, () => _IosObject(byId[id]!));
    for (final node in reverseNodeOrder ? update.reversed : update) {
      final object = get(node.id)..node = node;
      final children = [for (final id in node.children) get(id)];
      final hit = [for (final id in node.hit) get(id)];
      for (final c in object.children) {
        c.parent = null;
      }
      object.children = children;
      for (final c in children) {
        c.parent = object;
      }
      for (final c in object.hit) {
        c.parent = null;
      }
      object.hit = hit;
      for (final c in hit) {
        c.parent = object;
      }
    }
    final live = <int>{};
    void mark(_IosObject o) {
      live.add(o.node.id);
      o.children.forEach(mark);
    }

    final root = objects[0];
    if (root != null) mark(root);
    for (final id in objects.keys.where((k) => !live.contains(k)).toList()) {
      for (final c in objects.remove(id)!.children) {
        c.parent = null;
      }
    }
  }
  return objects;
}

/// SemanticsObject.mm ConvertRectToGlobal walks the native parent pointers.
Rect _iosFrame(_IosObject object, double dpr) {
  var matrix = Matrix4.fromFloat64List(object.node.transform);
  for (var parent = object.parent; parent != null; parent = parent.parent) {
    matrix = Matrix4.fromFloat64List(parent.node.transform).multiplied(matrix);
  }
  return _logicalFrame(matrix, object.node.rect, dpr);
}

/// The Flutter-side frame in screen points, using the current semantics tree.
Rect flutterSemanticsFrame(SemanticsNode node, double dpr) {
  var matrix = node.transform ?? Matrix4.identity();
  for (var parent = node.parent; parent != null; parent = parent.parent) {
    matrix = (parent.transform ?? Matrix4.identity()).multiplied(matrix);
  }
  return _logicalFrame(matrix, node.rect, dpr);
}

Rect _logicalFrame(Matrix4 matrix, Rect rect, double dpr) {
  final frame = MatrixUtils.transformRect(matrix, rect);
  return Rect.fromLTRB(
    frame.left / dpr,
    frame.top / dpr,
    frame.right / dpr,
    frame.bottom / dpr,
  );
}
