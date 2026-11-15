import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'orbit_screen_pump_harness.dart';

/// BL-33: on the iPhone 13 (dpr 3) every expanded orbit person was reported at
/// exactly a third of its real frame (pixelp0 18x18 at 56,99), while the
/// header chrome was correct.
///
/// The iOS accessibility bridge keeps one native object per semantics node with
/// a parent pointer, and builds each frame by walking those pointers up to the
/// root (Flutter 3.47.2 SemanticsObject.mm:40-44 and :66-95). When an update
/// moves children to a new parent AND removes their old parent, the removed
/// object's dealloc (SemanticsObject.mm:285-297, called from
/// accessibility_bridge.mm:199-203) sets the parent of every child it still
/// lists to nil. The moved children then lose every ancestor transform,
/// including the device pixel ratio, so their whole subtree reports at 1/dpr.
///
/// This test records the real semantics updates the app sends, replays them
/// through a port of that bookkeeping, and requires the iOS frame of every
/// orbit person to equal its real frame after the arcs expand.
class _Update {
  _Update(this.id, this.rect, this.transform, this.children, this.hit);
  final int id;
  final Rect rect;
  final Float64List transform;
  final List<int> children;
  final List<int> hit;
}

final List<List<_Update>> _updates = [];

class _RecordingBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingBuilder(this._real);
  final ui.SemanticsUpdateBuilder _real;
  final List<_Update> _nodes = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    if (invocation.memberName == #updateNode) {
      _nodes.add(
        _Update(
          args[#id] as int,
          args[#rect] as Rect,
          args[#transform] as Float64List,
          List<int>.of(args[#childrenInTraversalOrder] as Int32List),
          List<int>.of(args[#childrenInHitTestOrder] as Int32List),
        ),
      );
      return Function.apply(_real.updateNode, const [], args);
    }
    if (invocation.memberName == #build) {
      _updates.add(List.of(_nodes));
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

class _RecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingBuilder(super.createSemanticsUpdateBuilder());
}

class _IosObject {
  _IosObject(this.node);
  _Update node;
  _IosObject? parent;
  List<_IosObject> children = [];
  List<_IosObject> hit = [];
}

/// accessibility_bridge.mm UpdateSemantics: per node setChildren then
/// setChildrenInHitTestOrder (each nils the old children's parent, then sets
/// the new children's parent), then removal of unreachable objects.
Map<int, _IosObject> _replayIos(List<List<_Update>> updates) {
  final objects = <int, _IosObject>{};
  for (final update in updates) {
    final byId = {for (final n in update) n.id: n};
    _IosObject get(int id) => objects.putIfAbsent(id, () => _IosObject(byId[id]!));
    for (final node in update) {
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

/// SemanticsObject.mm ConvertRectToGlobal: the parent-pointer chain, then
/// divide by the screen scale.
Rect _iosFrame(_IosObject object, double dpr) {
  var m = Matrix4.fromFloat64List(object.node.transform);
  for (var p = object.parent; p != null; p = p.parent) {
    m = Matrix4.fromFloat64List(p.node.transform).multiplied(m);
  }
  final r = MatrixUtils.transformRect(m, object.node.rect);
  return Rect.fromLTRB(r.left / dpr, r.top / dpr, r.right / dpr, r.bottom / dpr);
}

Rect _realFrame(SemanticsNode node, double dpr) {
  var m = node.transform ?? Matrix4.identity();
  for (var p = node.parent; p != null; p = p.parent) {
    m = (p.transform ?? Matrix4.identity()).multiplied(m);
  }
  final r = MatrixUtils.transformRect(m, node.rect);
  return Rect.fromLTRB(r.left / dpr, r.top / dpr, r.right / dpr, r.bottom / dpr);
}

String _fmt(Rect r) =>
    '${r.left.round()},${r.top.round()} '
    '${r.width.round()}x${r.height.round()}';

OrbitItem _friend(int i) => OrbitFriendItem(
  OrbitFriend(
    contact: ContactModel(
      peerId: 'peer-$i',
      publicKey: 'pk-$i',
      rendezvous: '/ip4/127.0.0.1/tcp/400$i',
      username: 'friend$i',
      signature: 'sig-$i',
      scannedAt: '2024-01-01T00:00:00Z',
    ),
    messageCount: i,
    unreadCount: 0,
    lastMessageTimestamp: '2024-01-01T00:00:00Z',
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 90));
  }
}

void main() {
  _RecordingBinding();

  testWidgets('BL-33 expanded orbit people keep their real frames on iOS', (
    tester,
  ) async {
    const dpr = 3.0;
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844) * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildOrbitScreenHarness(
        viewMode: OrbitViewMode.innerCircle,
        header: OrbitHeaderProjection(
          userPeerId: 'me',
          innerItems: [for (var i = 0; i < 24; i++) _friend(i)],
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byType(OverflowBadge));
    await _settle(tester);

    final ios = _replayIos(_updates);
    final people = <SemanticsNode>[];
    void walk(SemanticsNode node) {
      if (node.label.startsWith('Open chat with')) people.add(node);
      node.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(
      tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
    );
    expect(people.length, greaterThan(13), reason: 'the arcs are open');

    final wrong = [
      for (final node in people)
        if (_fmt(_iosFrame(ios[node.id]!, dpr)) != _fmt(_realFrame(node, dpr)))
          '${node.label}: ios ${_fmt(_iosFrame(ios[node.id]!, dpr))}, '
              'real ${_fmt(_realFrame(node, dpr))}',
    ];
    expect(wrong, isEmpty);
    semantics.dispose();
  });
}
