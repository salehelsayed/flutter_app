import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_depth_surface.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/depth_fixtures.dart';

typedef _Sent = ({String text, String postId, String messageId});

void main() {
  late List<_Sent> sent;
  late List<String> chats, opened;
  late Map<String, PostModel> thoughts;
  late ValueNotifier<int> reset;
  late Completer<ThoughtReplyStatus>? hold;
  late ThoughtReplyStatus result;
  late StreamController<({String messageId, ThoughtReplyStatus status})>
  statuses;
  VoidCallback? back;

  setUp(() {
    sent = [];
    chats = [];
    opened = [];
    thoughts = {for (var i = 0; i < 4; i++) 'peer-$i': depthThought(i)};
    reset = ValueNotifier(0);
    hold = null;
    result = ThoughtReplyStatus.sent;
    statuses = StreamController.broadcast();
    back = null;
  });

  Future<void> mount(
    WidgetTester tester, {
    bool rtl = false,
    bool reduceMotion = true,
    Size size = const Size(390, 844),
    double topClearance = 0,
    double bottomClearance = 0,
    bool answers = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        locale: rtl ? const Locale('ar') : const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: OrbitDepthSurface(
            items: [
              for (var i = 0; i < 4; i++) OrbitFriendItem(depthFriend(i)),
            ],
            thoughts: thoughts,
            topClearance: topClearance,
            bottomClearance: bottomClearance,
            nowProvider: () => depthNow,
            resetSignal: reset,
            onFriendTap: (friend) => chats.add(friend.peerId),
            onThoughtTap: opened.add,
            onBackActionChanged: (value) => back = value,
            onReply: answers
                ? (text, postId, messageId) {
                    sent.add((
                      text: text,
                      postId: postId,
                      messageId: messageId,
                    ));
                    return hold?.future ?? Future.value(result);
                  }
                : null,
            replyStatusChanges: statuses.stream,
            child: const SizedBox.expand(child: Text('Flat circle')),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    reset.dispose();
    await statuses.close();
  }

  Future<void> rest(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.timedDrag(
      find.byType(OrbitDepthSurface),
      const Offset(0, -220),
      const Duration(seconds: 1),
    );
    await rest(tester);
  }

  Future<void> leave(WidgetTester tester) async {
    back!();
    await rest(tester);
  }

  Finder bar(int i) => find.byKey(ValueKey('orbit-depth-answers-post-$i'));
  Finder react(String name) => find.byKey(ValueKey('orbit-depth-react-$name'));
  final replyButton = find.byKey(const ValueKey('orbit-depth-reply'));
  final composer = find.byKey(const ValueKey('orbit-depth-composer'));
  final composerField = find.descendant(
    of: composer,
    matching: find.byType(TextField),
  );
  final status = find.byKey(const ValueKey('orbit-depth-answer-status'));
  final retry = find.byKey(const ValueKey('orbit-depth-answer-retry'));

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.tap(target, warnIfMissed: false);
    await rest(tester);
  }

  testWidgets('the bar shows under the focused friend\'s thought only, in '
      'the bottom fifth, with the four reactions in order then Reply', (
    tester,
  ) async {
    await mount(tester);
    expect(bar(0), findsNothing);
    await enter(tester);
    expect(bar(0), findsOneWidget);
    expect(bar(1), findsNothing);
    final xs = [
      for (final name in ['love', 'laugh', 'fire', 'applause'])
        tester.getCenter(react(name)).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    expect(tester.getSize(react('love')), const Size(52, 52));
    expect(
      tester.getTopLeft(replyButton).dx,
      greaterThan(tester.getTopRight(react('applause')).dx),
    );
    expect(find.text('Reply'), findsOneWidget);
    expect(tester.getTopLeft(bar(0)).dy, greaterThan(844 * .8));
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('orbit-depth-card-slot')))
          .dy,
      lessThan(tester.getTopLeft(bar(0)).dy),
    );
    await finish(tester);
  });

  testWidgets('without a reply sender there is no bar', (tester) async {
    await mount(tester, answers: false);
    await enter(tester);
    expect(bar(0), findsNothing);
    await finish(tester);
  });

  testWidgets('a reaction tap sends exactly one quoted reply with its glyph '
      'and stays in 3D with the emoji pressed and "sent"', (tester) async {
    await mount(tester);
    await enter(tester);
    await tap(tester, react('love'));
    expect(sent.map((s) => (s.text, s.postId)), [('❤️', 'post-0')]);
    expect(sent.single.messageId, isNotEmpty);
    expect(find.byKey(const ValueKey('orbit-depth-stage')), findsOneWidget);
    expect(opened, isEmpty);
    expect(chats, isEmpty);
    expect(
      tester.getSemantics(react('love')),
      isSemantics(label: 'React with love', isSelected: true),
    );
    expect(
      tester.getSemantics(react('laugh')),
      isSemantics(label: 'React with a laugh', isSelected: false),
    );
    expect(
      find.descendant(of: status, matching: find.text('sent')),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('a second tap on the same emoji in one visit sends nothing, '
      'another emoji sends, and a new visit sends again', (tester) async {
    await mount(tester);
    await enter(tester);
    await tap(tester, react('fire'));
    await tap(tester, react('fire'));
    expect(sent.map((s) => s.text), ['🔥']);
    await tap(tester, react('laugh'));
    expect(sent.map((s) => s.text), ['🔥', '😂']);
    await leave(tester);
    expect(bar(0), findsNothing);
    await enter(tester);
    await tap(tester, react('fire'));
    expect(sent.map((s) => s.text), ['🔥', '😂', '🔥']);
    expect(sent.map((s) => s.messageId).toSet(), hasLength(3));
    await finish(tester);
  });

  testWidgets('while sending it says Sending..., a failure offers Retry, and '
      'Retry resends once with the same message id', (tester) async {
    await mount(tester);
    await enter(tester);
    hold = Completer();
    await tap(tester, react('applause'));
    expect(
      find.descendant(of: status, matching: find.text('Sending...')),
      findsOneWidget,
    );
    expect(retry, findsNothing);
    hold!.complete(ThoughtReplyStatus.failed);
    await rest(tester);
    expect(
      find.descendant(
        of: status,
        matching: find.text('Message failed to send. Try again.'),
      ),
      findsOneWidget,
    );
    hold = null;
    await tap(tester, retry);
    expect(sent.map((s) => s.text), ['👏', '👏']);
    expect(sent[1].messageId, sent[0].messageId);
    expect(
      find.descendant(of: status, matching: find.text('sent')),
      findsOneWidget,
    );
    expect(retry, findsNothing);
    await tap(tester, react('applause'));
    expect(sent, hasLength(2));
    await finish(tester);
  });

  testWidgets('a later delivery update turns Sending... into sent', (
    tester,
  ) async {
    await mount(tester);
    await enter(tester);
    result = ThoughtReplyStatus.queued;
    await tap(tester, react('love'));
    expect(
      find.descendant(of: status, matching: find.text('Sending...')),
      findsOneWidget,
    );
    statuses.add((
      messageId: sent.single.messageId,
      status: ThoughtReplyStatus.sent,
    ));
    await rest(tester);
    expect(
      find.descendant(of: status, matching: find.text('sent')),
      findsOneWidget,
    );
    await finish(tester);
  });

  for (final lateResult in [
    ThoughtReplyStatus.queued,
    ThoughtReplyStatus.failed,
  ]) {
    testWidgets('a "sent" update stays sent when the held send then returns '
        '${lateResult.name}', (tester) async {
      await mount(tester);
      await enter(tester);
      hold = Completer();
      await tap(tester, react('love'));
      statuses.add((
        messageId: sent.single.messageId,
        status: ThoughtReplyStatus.sent,
      ));
      await rest(tester);
      hold!.complete(lateResult);
      await rest(tester);
      expect(
        find.descendant(of: status, matching: find.text('sent')),
        findsOneWidget,
      );
      expect(retry, findsNothing);
      await tap(tester, react('love'));
      expect(sent.map((s) => s.text), ['❤️']);
      await finish(tester);
    });
  }

  testWidgets('a screen reader tap on each reaction sends it once, and on '
      'Reply, Send and outside works the composer', (tester) async {
    final handle = tester.ensureSemantics();
    await mount(tester);
    await enter(tester);
    Future<void> activate(Finder target) async {
      final node = tester.getSemantics(target);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: '$target has no tap action',
      );
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await rest(tester);
    }

    for (final name in ['love', 'laugh', 'fire', 'applause']) {
      await activate(react(name));
    }
    expect(sent.map((s) => s.text), ['❤️', '😂', '🔥', '👏']);

    await activate(replyButton);
    expect(composer, findsOneWidget);
    await activate(find.byKey(const ValueKey('orbit-depth-composer-dismiss')));
    expect(composer, findsNothing);

    await activate(replyButton);
    await tester.enterText(composerField, 'by voice over');
    await rest(tester);
    await activate(
      find.descendant(
        of: composer,
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
    );
    expect(sent.map((s) => s.text), ['❤️', '😂', '🔥', '👏', 'by voice over']);
    expect(composer, findsNothing);
    await finish(tester);
    handle.dispose();
  });

  testWidgets('Reply opens a text-only composer in place; Send uses the same '
      'sender, closes it and stays in 3D showing "sent"', (tester) async {
    await mount(tester);
    await enter(tester);
    await tap(tester, replyButton);
    expect(composer, findsOneWidget);
    expect(find.text('Reply to Friend 0…'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);
    expect(find.byKey(const ValueKey('composer-attach-button')), findsNothing);
    expect(find.byKey(const ValueKey('voice-record-button')), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byKey(const ValueKey('orbit-depth-card-post-0')), findsOne);
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('orbit-depth-card-post-0')))
          .dy,
      lessThanOrEqualTo(tester.getTopLeft(composer).dy),
    );
    await tester.enterText(composerField, 'looks great');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: composer,
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
    );
    await rest(tester);
    expect(sent.map((s) => (s.text, s.postId)), [('looks great', 'post-0')]);
    expect(composer, findsNothing);
    expect(find.byKey(const ValueKey('orbit-depth-stage')), findsOneWidget);
    expect(opened, isEmpty);
    expect(chats, isEmpty);
    expect(find.text('Open chat'), findsNothing);
    expect(
      find.descendant(of: status, matching: find.text('sent')),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('tapping outside closes the composer and keeps the draft for '
      'this visit only', (tester) async {
    await mount(tester);
    await enter(tester);
    await tap(tester, replyButton);
    await tester.enterText(composerField, 'half a thought');
    await tester.pump();
    await tap(
      tester,
      find.byKey(const ValueKey('orbit-depth-composer-dismiss')),
    );
    expect(composer, findsNothing);
    expect(sent, isEmpty);
    expect(opened, isEmpty);
    await tap(tester, replyButton);
    expect(
      tester.widget<TextField>(composerField).controller!.text,
      'half a thought',
    );
    await tap(
      tester,
      find.byKey(const ValueKey('orbit-depth-composer-dismiss')),
    );
    await leave(tester);
    await enter(tester);
    await tap(tester, replyButton);
    expect(tester.widget<TextField>(composerField).controller!.text, '');
    await finish(tester);
  });

  testWidgets('hiding the keyboard closes the composer', (tester) async {
    await mount(tester);
    await enter(tester);
    await tap(tester, replyButton);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await rest(tester);
    expect(composer, findsOneWidget);
    tester.view.viewInsets = FakeViewPadding.zero;
    await rest(tester);
    expect(composer, findsNothing);
    tester.view.resetViewInsets();
    await finish(tester);
  });

  testWidgets('the avatar tap still opens the chat', (tester) async {
    await mount(tester);
    await enter(tester);
    await tap(tester, find.byKey(const ValueKey('orbit-depth-face-peer-0')));
    expect(chats, ['peer-0']);
    expect(sent, isEmpty);
    await finish(tester);
  });

  testWidgets('right to left mirrors the bar: reactions from the right, '
      'Reply on the left', (tester) async {
    await mount(tester, rtl: true);
    await enter(tester);
    final love = tester.getCenter(react('love')).dx;
    final laugh = tester.getCenter(react('laugh')).dx;
    expect(love, greaterThan(laugh));
    expect(
      tester.getTopRight(replyButton).dx,
      lessThan(tester.getTopLeft(react('applause')).dx),
    );
    expect(find.text('رد'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Reduce Motion cross-fades the bar to the next friend in 200 ms '
      'with no slide', (tester) async {
    await mount(tester);
    await enter(tester);
    final restingTop = tester.getTopLeft(bar(0)).dy;
    await tester.tap(find.byKey(const ValueKey('orbit-depth-face-peer-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(bar(0), findsOneWidget);
    expect(bar(1), findsOneWidget);
    expect(tester.getTopLeft(bar(1)).dy, restingTop);
    final fading = tester.widget<FadeTransition>(
      find.ancestor(of: bar(1), matching: find.byType(FadeTransition)).first,
    );
    expect(fading.opacity.value, closeTo(.5, .01));
    await tester.pump(const Duration(milliseconds: 150));
    expect(bar(0), findsNothing);
    expect(bar(1), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the bar ignores taps while the ring is turning', (tester) async {
    await mount(tester, reduceMotion: false);
    await enter(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('orbit-depth-face-peer-1')));
    var tapsWhileTurning = 0;
    for (var frame = 0; frame < 120 && tapsWhileTurning < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final opacity = tester
          .widget<Opacity>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('orbit-depth-answers-slot')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      if (opacity < .2 && react('love').evaluate().isNotEmpty) {
        await tester.tap(react('love').first, warnIfMissed: false);
        tapsWhileTurning++;
      }
    }
    expect(tapsWhileTurning, greaterThan(0));
    expect(sent, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    await tap(tester, react('love'));
    expect(sent.map((s) => (s.text, s.postId)), [('❤️', 'post-1')]);
    await finish(tester);
  });

  testWidgets('on a 375x667 phone every target stays at least 44 pt', (
    tester,
  ) async {
    await mount(
      tester,
      size: const Size(375, 667),
      topClearance: 56,
      bottomClearance: 80,
    );
    await enter(tester);
    for (final name in ['love', 'laugh', 'fire', 'applause']) {
      expect(tester.getSize(react(name)), const Size(44, 44));
    }
    expect(tester.getSize(replyButton).height, 44);
    expect(tester.getSize(replyButton).width, greaterThanOrEqualTo(44));
    expect(tester.getBottomLeft(bar(0)).dy, lessThanOrEqualTo(667 - 80));
    await finish(tester);
  });
}
