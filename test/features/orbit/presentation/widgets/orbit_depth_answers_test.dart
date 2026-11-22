import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_depth_surface.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_draft.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/depth_fixtures.dart';

typedef _Sent = ({String text, String postId, String messageId});

void main() {
  late List<_Sent> sent;
  late List<String> chats, opened;
  late List<String> settledTurns;
  late Map<String, PostModel> thoughts;
  late DateTime now;
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
    settledTurns = [];
    thoughts = {for (var i = 0; i < 4; i++) 'peer-$i': depthThought(i)};
    now = depthNow;
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
    Future<List<PostMediaAttachmentModel>> Function(String)? load,
    ThoughtTextReplySender? onTextReply,
    Future<bool> Function(ThoughtReplyDraft)? validateGrace,
    ValueChanged<String>? onTypedReplySent,
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
            nowProvider: () => now,
            resetSignal: reset,
            onFriendTap: (friend) => chats.add(friend.peerId),
            onThoughtTap: opened.add,
            onSettled: (_, peerId, turned) {
              if (turned && peerId != null) settledTurns.add(peerId);
            },
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
            onTextReply: onTextReply,
            validateGrace: validateGrace,
            onTypedReplySent: onTypedReplySent,
            replyStatusChanges: statuses.stream,
            loadMedia: load,
            downloadMedia: load == null ? null : (item, _) async => item,
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
  final composerField = find.byKey(const ValueKey('thought-reply-field'));
  final composer = find.byKey(const ValueKey('thought-reply-quote'));
  final dock = find.byKey(const ValueKey('thought-reply-dock'));
  final stickers = find.byKey(const ValueKey('thought-reply-stickers'));
  final sendButton = find.byKey(const ValueKey('thought-reply-send'));
  final status = find.byKey(const ValueKey('orbit-depth-answer-status'));
  final retry = find.byKey(const ValueKey('orbit-depth-answer-retry'));

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.tap(target, warnIfMissed: false);
    await rest(tester);
  }

  Future<void> activate(WidgetTester tester, Finder target) async {
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

  testWidgets('the dock shows only under the focused friend, with four '
      'reactions and the sticker choice above the reply field', (tester) async {
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
    expect(tester.getSize(react('love')), const Size(44, 44));
    expect(
      tester.getTopLeft(stickers).dx,
      greaterThan(tester.getTopRight(react('applause')).dx),
    );
    expect(
      tester.getTopLeft(composerField).dy,
      greaterThan(tester.getBottomLeft(react('applause')).dy),
    );
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('orbit-depth-card-slot')))
          .dy,
      lessThan(tester.getTopLeft(bar(0)).dy),
    );
    await finish(tester);
  });

  testWidgets('REV4 a moved emoji gesture and independent taps within 300 ms '
      'send nothing', (tester) async {
    await mount(tester);
    await enter(tester);
    final fire = find.descendant(of: bar(0), matching: react('fire'));
    final swipe = await tester.startGesture(tester.getCenter(fire));
    await swipe.moveBy(const Offset(12, 0));
    await swipe.moveBy(const Offset(-12, 0));
    await swipe.up();
    await tester.pump();
    expect(
      sent,
      isEmpty,
      reason: 'a swipe ending over the chip is never a tap',
    );

    await tester.tap(fire, warnIfMissed: false);
    await tester.pump();
    expect(
      sent,
      isEmpty,
      reason: 'a new pointer does not clear the swipe guard',
    );

    await tester.pump(const Duration(milliseconds: 299));
    await tester.tap(fire, warnIfMissed: false);
    await tester.pump();
    expect(sent, isEmpty, reason: '299 ms is still inside the guard');

    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(fire);
    await tester.pump();
    expect(sent.map((send) => (send.text, send.postId)), [('🔥', 'post-0')]);
    await finish(tester);
  });

  testWidgets('REV4 the 300 ms guard starts at fling settlement', (
    tester,
  ) async {
    await mount(tester, reduceMotion: false);
    await enter(tester);
    await tester.pump(const Duration(seconds: 1));
    final fire = find.descendant(of: bar(0), matching: react('fire'));
    await tester.fling(fire, const Offset(-115, 0), 1800);
    for (var frame = 0; frame < 100 && settledTurns.isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(settledTurns, ['peer-1']);
    expect(sent, isEmpty);
    final landedFire = find.descendant(of: bar(1), matching: react('fire'));
    await tester.tap(landedFire, warnIfMissed: false);
    await tester.pump();
    expect(sent, isEmpty, reason: 'landing does not release the guard early');
    await tester.pump(const Duration(milliseconds: 299));
    await tester.tap(landedFire, warnIfMissed: false);
    await tester.pump();
    expect(sent, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(landedFire);
    await tester.pump();
    expect(sent.map((send) => (send.text, send.postId)), [('🔥', 'post-1')]);
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
      isSemantics(label: 'Sent ❤️ reaction', isSelected: true),
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
    for (final name in ['love', 'laugh', 'fire', 'applause']) {
      await activate(tester, react(name));
    }
    expect(sent.map((s) => s.text), ['❤️', '😂', '🔥', '👏']);

    await activate(tester, composerField);
    expect(composer, findsOneWidget);
    await activate(
      tester,
      find.byKey(const ValueKey('orbit-depth-composer-dismiss')),
    );
    expect(composer, findsNothing);

    await activate(tester, composerField);
    await tester.enterText(composerField, 'by voice over');
    await rest(tester);
    await activate(tester, sendButton);
    expect(sent.map((s) => s.text), ['❤️', '😂', '🔥', '👏', 'by voice over']);
    expect(composer, findsNothing);
    await finish(tester);
    handle.dispose();
  });

  testWidgets('a screen reader Retry after a drag in 3D resends the failed '
      'reaction once with the same message id', (tester) async {
    final handle = tester.ensureSemantics();
    await mount(tester);
    await enter(tester);
    result = ThoughtReplyStatus.failed;
    await tap(tester, react('applause'));
    expect(retry, findsOneWidget);
    result = ThoughtReplyStatus.sent;
    await enter(tester);
    expect(bar(0), findsOneWidget);
    await activate(tester, retry);
    expect(sent.map((s) => s.text), ['👏', '👏']);
    expect(sent[1].messageId, sent[0].messageId);
    expect(
      find.descendant(of: status, matching: find.text('sent')),
      findsOneWidget,
    );
    await finish(tester);
    handle.dispose();
  });

  testWidgets('a screen reader tap on the focused thought card opens it once', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await mount(tester);
    await enter(tester);
    await activate(
      tester,
      find.byKey(const ValueKey('orbit-depth-card-post-0')),
    );
    expect(opened, ['post-0']);
    expect(sent, isEmpty);
    await finish(tester);
    handle.dispose();
  });

  testWidgets('a screen reader tap on the focused thought\'s photo opens it '
      'once', (tester) async {
    final temp = Directory.systemTemp.createTempSync('orbit-depth-answers-');
    MediaFileManager.cacheDocumentsDir(temp.path);
    addTearDown(() {
      MediaFileManager.debugResetDocumentsDirCache();
      temp.deleteSync(recursive: true);
    });
    final file = File('${temp.path}/photo.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      );
    final photo = PostMediaAttachmentModel(
      mediaId: 'photo-0',
      postId: 'post-0',
      blobId: 'blob-0',
      kind: 'image',
      mime: 'image/png',
      sizeBytes: 68,
      localPath: file.path,
      downloadStatus: 'done',
      createdAt: depthNow.toIso8601String(),
    );
    thoughts['peer-0'] = depthThought(0, mediaKind: 'image');
    final handle = tester.ensureSemantics();
    await mount(tester, load: (_) async => [photo]);
    await enter(tester);
    await activate(
      tester,
      find.byKey(const ValueKey('media-grid-cell-post-0-blob-0')),
    );
    expect(opened, ['post-0']);
    await finish(tester);
    handle.dispose();
  });

  testWidgets('Reply opens a text-only composer in place; Send uses the same '
      'sender, closes it and stays in 3D showing "sent"', (tester) async {
    await mount(tester);
    await enter(tester);
    await tap(tester, composerField);
    expect(composer, findsOneWidget);
    expect(
      tester.widget<TextField>(composerField).decoration?.hintText,
      'Reply to Friend 0…',
    );
    expect(find.byIcon(Icons.mic), findsNothing);
    expect(find.byKey(const ValueKey('composer-attach-button')), findsNothing);
    expect(find.byKey(const ValueKey('voice-record-button')), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byKey(const ValueKey('orbit-depth-card-post-0')), findsOne);
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('orbit-depth-card-post-0')))
          .dy,
      lessThanOrEqualTo(tester.getTopLeft(dock).dy),
    );
    await tester.enterText(composerField, 'looks great');
    await tester.pump();
    await tester.tap(sendButton);
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

  testWidgets('tapping outside closes the composer and discards its reply', (
    tester,
  ) async {
    await mount(tester);
    await enter(tester);
    await tap(tester, composerField);
    await tester.enterText(composerField, 'half a thought');
    await tester.pump();
    await tap(
      tester,
      find.byKey(const ValueKey('orbit-depth-composer-dismiss')),
    );
    expect(composer, findsNothing);
    expect(sent, isEmpty);
    expect(opened, isEmpty);
    await tap(tester, composerField);
    expect(tester.widget<TextField>(composerField).controller!.text, isEmpty);
    await tap(
      tester,
      find.byKey(const ValueKey('orbit-depth-composer-dismiss')),
    );
    await leave(tester);
    await enter(tester);
    await tap(tester, composerField);
    expect(tester.widget<TextField>(composerField).controller!.text, isEmpty);
    await finish(tester);
  });

  testWidgets(
    'hiding the keyboard closes the composer and discards its reply',
    (tester) async {
      await mount(tester);
      await enter(tester);
      await tap(tester, composerField);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await rest(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(composerField, 'unsent reply');
      tester.view.viewInsets = FakeViewPadding.zero;
      await rest(tester);
      expect(composer, findsNothing);
      expect(sent, isEmpty);
      await tap(tester, composerField);
      expect(tester.widget<TextField>(composerField).controller!.text, isEmpty);
      tester.view.resetViewInsets();
      await finish(tester);
    },
  );

  for (final (how, hide) in <(String, void Function(WidgetTester))>[
    (
      'the keyboard inset drops',
      (t) => t.view.viewInsets = FakeViewPadding.zero,
    ),
    (
      'the field loses focus',
      (t) => FocusManager.instance.primaryFocus?.unfocus(),
    ),
  ]) {
    testWidgets('a system Back in the same frame as $how closes only the '
        'composer and discards its reply', (tester) async {
      await mount(tester);
      await enter(tester);
      await tap(tester, composerField);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await rest(tester);
      await tester.enterText(composerField, 'half a thought');
      await tester.pump();
      hide(tester);
      await tester.binding.handlePopRoute().timeout(const Duration(seconds: 3));
      await rest(tester);
      tester.view.viewInsets = FakeViewPadding.zero;
      await rest(tester);
      expect(composer, findsNothing);
      expect(find.byKey(const ValueKey('orbit-depth-stage')), findsOneWidget);
      expect(bar(0), findsOneWidget);
      expect(sent, isEmpty);
      await tap(tester, composerField);
      expect(tester.widget<TextField>(composerField).controller!.text, isEmpty);
      tester.view.resetViewInsets();
      await finish(tester);
    });
  }

  testWidgets('typing through expiry keeps the exact reply until an admitted '
      'send finishes', (tester) async {
    final expiry = depthNow.add(const Duration(seconds: 2));
    thoughts['peer-0'] = depthThought(
      0,
    ).copyWith(expiresAt: expiry.toIso8601String());
    final result = Completer<ThoughtReplyStatus>();
    addTearDown(() {
      if (!result.isCompleted) result.complete(ThoughtReplyStatus.failed);
    });
    ThoughtReplyDraft? admitted;
    await mount(
      tester,
      validateGrace: (draft) async => draft.postId == 'post-0',
      onTextReply: (text, postId, messageId, draft) {
        sent.add((text: text, postId: postId, messageId: messageId));
        admitted = draft;
        return result.future.timeout(const Duration(seconds: 3));
      },
    );
    await enter(tester);
    await tap(tester, composerField);
    await tester.enterText(composerField, 'which day works?');

    now = expiry;
    await tester.pump(const Duration(seconds: 2));
    await rest(tester);
    expect(composer, findsOneWidget);
    expect(
      tester.widget<TextField>(composerField).controller!.text,
      'which day works?',
    );
    expect(react('love'), findsNothing);

    now = expiry.add(const Duration(seconds: 59));
    await tester.pump(const Duration(seconds: 1));
    await tap(tester, sendButton);
    expect(sent.single.postId, 'post-0');
    expect(admitted?.expiresAt, expiry);

    now = expiry.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    expect(composer, findsOneWidget);
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
    expect(sent, hasLength(1));

    result.complete(ThoughtReplyStatus.sent);
    await rest(tester);
    expect(composer, findsNothing);
    expect(find.byKey(const ValueKey('orbit-depth-stage')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a typed reply finishing after Back does not reopen chat', (
    tester,
  ) async {
    final result = Completer<ThoughtReplyStatus>();
    addTearDown(() {
      if (!result.isCompleted) result.complete(ThoughtReplyStatus.failed);
    });
    await mount(
      tester,
      onTypedReplySent: chats.add,
      onTextReply: (_, _, _, _) =>
          result.future.timeout(const Duration(seconds: 3)),
    );
    await enter(tester);
    await tap(tester, composerField);
    await tester.enterText(composerField, 'which day works?');
    await rest(tester);
    await tap(tester, sendButton);
    expect(composer, findsNothing);
    await leave(tester);
    result.complete(ThoughtReplyStatus.sent);
    await rest(tester);
    expect(chats, isEmpty);
    expect(find.byKey(const ValueKey('orbit-depth-stage')), findsNothing);
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

  testWidgets('right to left mirrors the reaction and send controls', (
    tester,
  ) async {
    await mount(tester, rtl: true);
    await enter(tester);
    final love = tester.getCenter(react('love')).dx;
    final laugh = tester.getCenter(react('laugh')).dx;
    expect(love, greaterThan(laugh));
    expect(
      tester.getTopRight(stickers).dx,
      lessThan(tester.getTopLeft(react('applause')).dx),
    );
    expect(
      tester.getCenter(sendButton).dx,
      lessThan(tester.getCenter(composerField).dx),
    );
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

  testWidgets('on a 375x667 phone every target stays at least 44 pt and '
      'the bar keeps its place above the bottom', (tester) async {
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
    for (final target in [stickers, composerField, sendButton]) {
      expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
    }
    // The dock leaves room for its status row at the bottom of the ring.
    expect(tester.getBottomLeft(dock).dy, lessThanOrEqualTo(667 - 44));
    await finish(tester);
  });

  double shownOpacity(WidgetTester tester, Finder target) {
    var opacity = 1.0;
    for (
      RenderObject? box = tester.renderObject(target);
      box != null;
      box = box.parent
    ) {
      if (box is RenderOpacity) opacity *= box.opacity;
    }
    return opacity;
  }

  testWidgets('an empty Reply shows Send in its slot, disabled until there '
      'is text, then Send sends', (tester) async {
    final handle = tester.ensureSemantics();
    await mount(tester);
    await enter(tester);
    await tap(tester, composerField);
    final send = sendButton;
    expect(send, findsOneWidget);
    expect(shownOpacity(tester, send), 1.0);
    expect(tester.widget<IconButton>(send).tooltip, 'Send reply');
    expect(
      tester
          .getSemantics(send)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    await tap(tester, send);
    expect(sent, isEmpty);
    expect(composer, findsOneWidget);

    await tester.enterText(composerField, 'nice one');
    await rest(tester);
    expect(sent, isEmpty, reason: 'typing after a disabled tap never sends');
    expect(composer, findsOneWidget);
    expect(shownOpacity(tester, send), 1.0);
    expect(
      tester
          .getSemantics(send)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tap(tester, send);
    expect(sent.map((s) => (s.text, s.postId)), [('nice one', 'post-0')]);
    expect(composer, findsNothing);
    await finish(tester);
    handle.dispose();
  });

  for (final size in const [Size(360, 640), Size(390, 844), Size(412, 915)]) {
    testWidgets('on a ${size.width.toInt()}x${size.height.toInt()} phone the '
        'reply field sits near the bottom after a swipe up, and the dock '
        'fits between the thought and ring after a swipe down', (tester) async {
      await mount(tester, reduceMotion: false, size: size);
      await enter(tester);
      await tester.pumpAndSettle();
      final upDock = tester.getRect(bar(0));
      final field = tester.getRect(composerField);
      expect(field.center.dy, greaterThanOrEqualTo(size.height * .8));
      expect(upDock.contains(field.topLeft), isTrue);
      expect(
        upDock.contains(field.bottomRight - const Offset(.01, .01)),
        isTrue,
      );
      expect(upDock.bottom, lessThanOrEqualTo(size.height));
      await leave(tester);
      await tester.pumpAndSettle();

      await tester.timedDrag(
        find.byType(OrbitDepthSurface),
        const Offset(0, 220),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('orbit-depth-card-post-0'));
      final face = find.byKey(const ValueKey('orbit-depth-face-peer-0'));
      expect(
        tester.getBottomLeft(card).dy,
        lessThanOrEqualTo(tester.getTopLeft(bar(0)).dy),
      );
      expect(
        tester.getBottomLeft(bar(0)).dy,
        lessThanOrEqualTo(tester.getTopLeft(face).dy),
      );
      await finish(tester);
    });
  }

  testWidgets('with motion on, the bar fades with the thought on every frame '
      'of a held turn', (tester) async {
    await mount(tester, reduceMotion: false);
    await enter(tester);
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('orbit-depth-card-post-0'));
    final finger = await tester.startGesture(const Offset(195, 500));
    final seen = <(double, double)>[];
    for (var step = 0; step < 3; step++) {
      await finger.moveBy(const Offset(-15, 0));
      await tester.pump(const Duration(milliseconds: 16));
      seen.add((shownOpacity(tester, bar(0)), shownOpacity(tester, card)));
    }
    for (final (barOpacity, cardOpacity) in seen) {
      expect(barOpacity, closeTo(cardOpacity, .001));
    }
    expect(seen.last.$1, lessThan(.3));
    await finger.up();
    await tester.pumpAndSettle();
    await finish(tester);
  });
}
