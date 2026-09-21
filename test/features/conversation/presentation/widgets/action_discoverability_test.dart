import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_composer.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';

Widget _app(Widget child, String locale) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

SemanticsNode _action(
  WidgetTester tester,
  String label, {
  bool enabled = true,
  bool includesContent = false,
}) {
  final matches = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.label == label ||
        node.getSemanticsData().tooltip == label ||
        (includesContent && node.label.startsWith('$label\n'))) {
      matches.add(node);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  expect(matches, hasLength(1), reason: 'One active semantic node for $label');
  final node = matches.single;
  final data = node.getSemanticsData();
  expect(data.flagsCollection.isButton, isTrue, reason: label);
  expect(
    data.flagsCollection.isEnabled != ui.Tristate.none,
    isTrue,
    reason: label,
  );
  expect(
    data.flagsCollection.isEnabled == ui.Tristate.isTrue,
    enabled,
    reason: label,
  );
  expect(data.hasAction(ui.SemanticsAction.tap), enabled, reason: label);
  expect(find.text(label), findsNothing, reason: 'No persistent caption');
  return node;
}

void _activate(WidgetTester tester, SemanticsNode node) => tester
    .binding
    .renderViews
    .single
    .owner!
    .semanticsOwner!
    .performAction(node.id, ui.SemanticsAction.tap);

const _names = {
  'en': [
    'Back',
    'View contact profile',
    'Conversation options',
    'Add attachment',
    'Send message',
    'Start voice call',
    'Starting voice call',
    'Voice calling is unavailable for this device',
  ],
  'de': [
    'Zurück',
    'Kontaktprofil anzeigen',
    'Unterhaltungsoptionen',
    'Anhang hinzufügen',
    'Nachricht senden',
    'Sprachanruf starten',
    'Sprachanruf wird gestartet',
    'Sprachanrufe sind auf diesem Gerät nicht verfügbar',
  ],
  'ar': [
    'رجوع',
    'عرض ملف جهة الاتصال',
    'خيارات المحادثة',
    'إضافة مرفق',
    'إرسال رسالة',
    'بدء مكالمة صوتية',
    'جارٍ بدء المكالمة الصوتية',
    'المكالمات الصوتية غير متاحة على هذا الجهاز',
  ],
};

void main() {
  for (final entry in _names.entries) {
    final locale = entry.key;
    final names = entry.value;
    testWidgets(
      'A02 recording phase names hints and review availability $locale',
      (tester) async {
        final handle = tester.ensureSemantics();
        final labels = {
          'en': [
            'Record voice message',
            'Cancel recording start',
            'Stop and send voice message',
            'Finishing voice message',
            'Send voice message',
            'Discard recording',
          ],
          'de': [
            'Sprachnachricht aufnehmen',
            'Aufnahmestart abbrechen',
            'Aufnahme beenden und Sprachnachricht senden',
            'Sprachnachricht wird fertiggestellt',
            'Sprachnachricht senden',
            'Aufnahme verwerfen',
          ],
          'ar': [
            'تسجيل رسالة صوتية',
            'إلغاء بدء التسجيل',
            'إيقاف التسجيل وإرسال الرسالة الصوتية',
            'جارٍ إنهاء الرسالة الصوتية',
            'إرسال الرسالة الصوتية',
            'حذف التسجيل',
          ],
        }[locale]!;
        final hints = {
          'en': [
            'Tap to start recording',
            'Tap to cancel starting the recording',
            'Tap to stop recording and send the voice message',
          ],
          'de': [
            'Tippen, um die Aufnahme zu starten',
            'Tippen, um den Aufnahmestart abzubrechen',
            'Tippen, um die Aufnahme zu beenden und die Sprachnachricht zu senden',
          ],
          'ar': [
            'اضغط لبدء التسجيل',
            'اضغط لإلغاء بدء التسجيل',
            'اضغط لإيقاف التسجيل وإرسال الرسالة الصوتية',
          ],
        }[locale]!;
        final calls = [0, 0, 0, 0];
        for (final phase in VoiceRecordingState.values) {
          await tester.pumpWidget(
            _app(
              ComposeArea(
                onSend: (_) {},
                recordingState: phase,
                onRecordStart: () => calls[0]++,
                onRecordStop: () => calls[1]++,
                onRecordCancel: () {},
                onReviewSend: () => calls[2]++,
                onReviewDiscard: () => calls[3]++,
              ),
              locale,
            ),
          );
          await tester.pump();
          final node = _action(
            tester,
            labels[phase.index],
            enabled: phase != VoiceRecordingState.stopping,
          );
          _action(tester, names[3], enabled: false);
          if (phase.index < 3) {
            expect(node.hint, hints[phase.index]);
            final tooltip = tester.widget<Tooltip>(
              find.byTooltip(labels[phase.index]),
            );
            expect(tooltip.triggerMode, TooltipTriggerMode.manual);
            _activate(tester, node);
          } else if (phase == VoiceRecordingState.stopping) {
            expect(node.hint, isEmpty);
            await tester.tap(find.byTooltip(labels[phase.index]));
          } else {
            _activate(tester, node);
            _activate(tester, _action(tester, labels[5]));
          }
        }
        expect(calls, [1, 2, 1, 1]);
        await tester.pumpWidget(
          _app(
            ComposeArea(
              onSend: (_) {},
              recordingState: VoiceRecordingState.reviewing,
            ),
            locale,
          ),
        );
        await tester.pump();
        _action(tester, labels[4], enabled: false);
        _action(tester, labels[5], enabled: false);
        handle.dispose();
      },
    );

    for (final group in [false, true]) {
      testWidgets('A02 screen phase propagation group=$group $locale', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final l10n = lookupAppLocalizations(Locale(locale));
        final namesByPhase = {
          VoiceRecordingState.idle: l10n.voice_record_action,
          VoiceRecordingState.arming: l10n.voice_cancel_start_action,
          VoiceRecordingState.recording: l10n.voice_stop_send_action,
          VoiceRecordingState.stopping: l10n.voice_finishing_label,
          if (!group)
            VoiceRecordingState.reviewing: l10n.voice_review_send_action,
        };
        final calls = [0, 0, 0, 0];
        for (final entry in namesByPhase.entries) {
          final Widget screen = group
              ? GroupConversationScreen(
                  group: GroupModel(
                    id: 'fixture',
                    name: 'Fixture',
                    type: GroupType.chat,
                    topicName: 'fixture',
                    createdAt: DateTime(2026),
                    createdBy: 'fixture',
                    myRole: GroupRole.admin,
                  ),
                  messages: const [],
                  onSend: (_) {},
                  onBack: () {},
                  initialLoadDone: true,
                  recordingState: entry.key,
                  onRecordStart: () => calls[0]++,
                  onRecordStop: () => calls[1]++,
                )
              : ConversationScreen(
                  contactPeerId: 'fixture',
                  contactUsername: 'Alice',
                  connectionDate: '2026',
                  messages: const [],
                  onSend: (_) {},
                  onBack: () {},
                  initialLoadDone: true,
                  showCallAction: true,
                  recordingState: entry.key,
                  onRecordStart: () => calls[0]++,
                  onRecordStop: () => calls[1]++,
                  onReviewSend: () => calls[2]++,
                  onReviewDiscard: () => calls[3]++,
                );
          await tester.pumpWidget(_app(screen, locale));
          await tester.pump();
          final node = _action(
            tester,
            entry.value,
            enabled: entry.key != VoiceRecordingState.stopping,
          );
          if (entry.key != VoiceRecordingState.stopping) {
            _activate(tester, node);
          }
          if (entry.key == VoiceRecordingState.reviewing) {
            _activate(
              tester,
              _action(tester, l10n.voice_review_discard_action),
            );
          }
          if (!group) {
            _action(tester, l10n.voice_call_unavailable, enabled: false);
          }
        }
        expect(calls, group ? [1, 2, 0, 0] : [1, 2, 1, 1]);
        handle.dispose();
      });
    }

    testWidgets('A02 group header actions $locale', (tester) async {
      final handle = tester.ensureSemantics();
      var backs = 0;
      var infos = 0;
      final infoName = {
        'en': 'Group information',
        'de': 'Gruppeninformationen',
        'ar': 'معلومات المجموعة',
      }[locale]!;
      await tester.pumpWidget(
        _app(
          GroupConversationScreen(
            group: GroupModel(
              id: 'fixture',
              name: 'Fixture',
              type: GroupType.chat,
              topicName: 'fixture',
              createdAt: DateTime(2026),
              createdBy: 'fixture',
              myRole: GroupRole.admin,
            ),
            messages: const [],
            onSend: (_) {},
            onBack: () => backs++,
            onInfo: () => infos++,
            initialLoadDone: true,
          ),
          locale,
        ),
      );
      await tester.pump();
      _activate(tester, _action(tester, names[0]));
      _activate(tester, _action(tester, infoName));
      expect([backs, infos], [1, 1]);
      handle.dispose();
    });

    testWidgets('A02 header localized actions activate once $locale', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final calls = [0, 0, 0, 0];
      await tester.pumpWidget(
        _app(
          ConversationHeader(
            contactPeerId: 'fixture-peer',
            contactUsername: 'Alice',
            connectionDate: '2026',
            onBack: () => calls[0]++,
            onAvatarTap: () => calls[1]++,
            onOverflow: () => calls[2]++,
            showCallAction: true,
            callActionEnabled: true,
            onCall: () => calls[3]++,
          ),
          locale,
        ),
      );
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        _activate(tester, _action(tester, names[i], includesContent: i == 1));
      }
      _activate(tester, _action(tester, names[5]));
      expect(calls, [1, 1, 1, 1]);
      await tester.pumpWidget(
        _app(
          ConversationHeader(
            contactPeerId: 'fixture-peer',
            contactUsername: 'Alice',
            connectionDate: '2026',
            onBack: () {},
            showCallAction: true,
            callActionInFlight: true,
          ),
          locale,
        ),
      );
      await tester.pump();
      _action(tester, names[2], enabled: false);
      _action(tester, names[6], enabled: false);
      expect(find.bySemanticsLabel(RegExp(names[1])), findsNothing);
      await tester.pumpWidget(
        _app(
          ConversationHeader(
            contactPeerId: 'fixture-peer',
            contactUsername: 'Alice',
            connectionDate: '2026',
            onBack: () {},
            showCallAction: true,
          ),
          locale,
        ),
      );
      await tester.pump();
      _action(tester, names[7], enabled: false);
      handle.dispose();
    });

    testWidgets('A02 composer named actions retain availability $locale', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var attaches = 0;
      final sends = <String>[];
      for (final state in ['ready', 'processing', 'sending', 'invalid']) {
        await tester.pumpWidget(
          _app(
            ComposeArea(
              key: ValueKey(state),
              onSend: sends.add,
              onAttach: () => attaches++,
              initialText: 'fixture',
              isProcessing: state == 'processing',
              isSending: state == 'sending',
              hasInvalidAttachment: state == 'invalid',
            ),
            locale,
          ),
        );
        await tester.pump();
        final attach = _action(
          tester,
          names[3],
          enabled: state != 'processing',
        );
        final send = _action(tester, names[4], enabled: state == 'ready');
        if (state != 'processing') _activate(tester, attach);
        if (state == 'ready') _activate(tester, send);
      }
      expect(attaches, 3);
      expect(sends, ['fixture']);
      handle.dispose();
    });

    testWidgets(
      'A02 Feed send uses framework semantics and stays focused $locale',
      (tester) async {
        final handle = tester.ensureSemantics();
        final sends = <String>[];
        await tester.pumpWidget(
          _app(
            FeedComposer(
              hintText: 'Reply',
              addAnotherHint: 'Again',
              onSend: sends.add,
            ),
            locale,
          ),
        );
        await tester.pump();
        _action(tester, names[4], enabled: false);
        await tester.enterText(find.byType(TextField), '  fixture  ');
        await tester.pump();
        _activate(tester, _action(tester, names[4]));
        await tester.pump();
        expect(sends, ['fixture']);
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
          isTrue,
        );
        _action(tester, names[4], enabled: false);
        handle.dispose();
      },
    );
  }
}
