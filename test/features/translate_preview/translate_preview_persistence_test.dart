import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/database/helpers/local_ai_preview_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_persistence.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_model_delivery_controller.dart';
import 'local_preview_fixture.dart';

class _Ai implements OnDeviceAi {
  int transcriptions = 0;
  int translations = 0;
  Completer<String>? pending;

  @override
  Future<String> transcribe(String path) async {
    transcriptions++;
    if (pending != null) return await pending!.future;
    return 'أنا في الطريق';
  }

  @override
  Future<String> translate(
    String source, {
    required String languageName,
  }) async {
    translations++;
    if (pending != null) return await pending!.future;
    return '$languageName result';
  }
}

Widget _host(Widget child, {String language = 'en'}) =>
    localizedApp(Scaffold(body: child), locale: Locale(language));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const voice = PreviewOwner.voiceAttachment('voice', messageId: 'message');
  const thought = PreviewOwner.thought('thought');

  testWidgets(
    'voice transcript and translation survive DB restart without model calls',
    (tester) async {
      final fixture = LocalPreviewFixture();
      await tester.runAsync(() async {
        await fixture.open();
        await fixture.seedVoice();
      });
      addTearDown(fixture.dispose);
      final ai = _Ai();
      Widget view({ModelDeliveryController? delivery}) => _host(
        TranscribePreview(
          audioPath: '/voice.m4a',
          owner: voice,
          persistence: fixture.store,
          ai: ai,
          delivery: delivery,
        ),
      );
      await tester.pumpWidget(view());
      await fixture.flush(tester);
      await tester.tap(find.text('Transcribe'));
      await fixture.flush(tester);
      expect(find.text('أنا في الطريق'), findsOneWidget);
      await tester.tap(find.text('See translation'));
      await fixture.flush(tester);
      expect(find.text('English result'), findsOneWidget);
      expect((ai.transcriptions, ai.translations), (1, 1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(fixture.reopen);
      final delivery = FakeModelDeliveryController(
        const ModelNotDownloaded(
          totalBytes: 100,
          freeBytes: 1000,
          onWifi: true,
        ),
      );
      await tester.pumpWidget(view(delivery: delivery));
      await fixture.flush(tester);
      expect(find.text('أنا في الطريق'), findsOneWidget);
      expect(find.text('English result'), findsOneWidget);
      expect((ai.transcriptions, ai.translations), (1, 1));
      expect(delivery.calls, isEmpty);
    },
  );

  testWidgets(
    'Thought text and photo caption reuse the same saved item on reopen',
    (tester) async {
      final fixture = LocalPreviewFixture();
      await tester.runAsync(() async {
        await fixture.open();
        await fixture.seedThought();
      });
      addTearDown(fixture.dispose);
      final ai = _Ai();
      Widget view(String surface) => _host(
        Column(
          key: ValueKey(surface),
          children: [
            Text(surface),
            TranslatePreview(
              text: 'أنا في الطريق',
              owner: thought,
              persistence: fixture.store,
              ai: ai,
            ),
          ],
        ),
      );
      await tester.pumpWidget(view('Thought text'));
      await fixture.flush(tester);
      await tester.tap(find.text('See translation'));
      await fixture.flush(tester);
      expect(find.text('English result'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(fixture.reopen);
      await tester.pumpWidget(view('Photo caption'));
      await fixture.flush(tester);
      expect(find.text('English result'), findsOneWidget);
      expect(ai.translations, 1);
    },
  );

  testWidgets(
    'live locale change hides output until asked and reuses each target',
    (tester) async {
      final fixture = LocalPreviewFixture();
      await tester.runAsync(() async {
        await fixture.open();
        await fixture.seedThought();
      });
      addTearDown(fixture.dispose);
      final ai = _Ai();
      final delivery = FakeModelDeliveryController(
        const ModelReady(sizeBytes: 1),
      );
      Widget view(String language) => _host(
        TranslatePreview(
          text: 'أنا في الطريق',
          owner: thought,
          persistence: fixture.store,
          ai: ai,
          delivery: delivery,
        ),
        language: language,
      );
      await tester.pumpWidget(view('en'));
      await fixture.flush(tester);
      await tester.tap(find.text('See translation'));
      await fixture.flush(tester);
      await tester.pumpWidget(view('de'));
      await fixture.flush(tester);
      expect(find.text('English result'), findsNothing);
      await tester.tap(find.text('Übersetzung anzeigen'));
      await fixture.flush(tester);
      expect(find.text('German result'), findsOneWidget);
      delivery.state.value = const ModelFailed();
      await tester.pumpWidget(view('en'));
      await fixture.flush(tester);
      expect(find.text('English result'), findsNothing);
      await tester.tap(find.text('Try again'));
      await fixture.flush(tester);
      expect(find.text('English result'), findsOneWidget);
      delivery.state.value = const ModelNotDownloaded(
        totalBytes: 100,
        freeBytes: 1000,
        onWifi: true,
      );
      await tester.pumpWidget(view('de'));
      await fixture.flush(tester);
      expect(find.text('German result'), findsNothing);
      await tester.tap(find.text('Übersetzung anzeigen'));
      await fixture.flush(tester);
      expect(find.text('German result'), findsOneWidget);
      expect(ai.translations, 2);
      expect(delivery.calls, isEmpty);
      expect(
        await tester.runAsync(() => fixture.db.query('local_ai_translations')),
        hasLength(2),
      );
    },
  );

  testWidgets('completed transcription saves after leaving the widget', (
    tester,
  ) async {
    final fixture = LocalPreviewFixture();
    await tester.runAsync(() async {
      await fixture.open();
      await fixture.seedVoice();
    });
    addTearDown(fixture.dispose);
    final ai = _Ai()..pending = Completer<String>();
    await tester.pumpWidget(
      _host(
        TranscribePreview(
          audioPath: '/voice.m4a',
          owner: voice,
          persistence: fixture.store,
          ai: ai,
        ),
      ),
    );
    await fixture.flush(tester);
    await tester.tap(find.text('Transcribe'));
    await fixture.flush(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    ai.pending!.complete('saved after leaving');
    await fixture.flush(tester);
    expect(
      await tester.runAsync(() => fixture.store.loadTranscript(voice)),
      'saved after leaving',
    );
    await fixture.flush(tester);
  });

  test(
    'delete, retained tombstone, and disappearing expiry erase local results',
    () async {
      final fixture = LocalPreviewFixture();
      await fixture.open();
      addTearDown(fixture.dispose);
      Future<void> save() async {
        expect(await fixture.store.saveTranscript(voice, 'transcript'), isTrue);
        expect(
          await fixture.store.saveTranslation(
            voice,
            'transcript',
            'en',
            'translation',
          ),
          isTrue,
        );
      }

      await fixture.seedVoice();
      await save();
      await fixture.db.delete(
        'messages',
        where: 'id = ?',
        whereArgs: ['message'],
      );
      expect(await fixture.db.query('local_ai_translations'), isEmpty);
      expect(
        (await fixture.db.query(
          'media_attachments',
        )).single['local_transcript'],
        isNull,
      );
      expect(await fixture.store.saveTranscript(voice, 'late'), isFalse);

      await fixture.db.delete('media_attachments');
      await fixture.seedVoice();
      await save();
      await fixture.db.update(
        'messages',
        {'hidden_at': '2030-01-01T00:00:00Z'},
        where: 'id = ?',
        whereArgs: ['message'],
      );
      expect(await fixture.db.query('local_ai_translations'), isEmpty);
      expect(
        (await fixture.db.query(
          'media_attachments',
        )).single['local_transcript'],
        isNull,
      );

      await fixture.db.delete('media_attachments');
      await fixture.db.delete('messages');
      await fixture.seedVoice();
      await fixture.db.update('messages', {
        'private_media_policy_version': 1,
        'private_media_mode': 'disappearing',
        'private_media_duration_seconds': 3600,
        'private_media_state': 'available',
        'private_media_expires_at_ms': fixture.nowMs + 1000,
      });
      await save();
      // Canonical high-water qualification must survive a wall-clock rollback.
      await fixture.db.update('messages', {
        'private_media_clock_high_water_ms': fixture.nowMs + 1001,
      });
      expect(await fixture.db.query('local_ai_translations'), isEmpty);
      expect(await fixture.store.loadTranscript(voice), isNull);
      expect(await fixture.store.saveTranscript(voice, 'late'), isFalse);
      expect(
        (await fixture.db.query(
          'media_attachments',
        )).single['local_transcript'],
        isNull,
      );
      expect(
        (await fixture.db.query('messages')).single['private_media_state'],
        'expired',
      );
    },
  );

  test('deleting a chat clears every retained attachment result', () async {
    final fixture = LocalPreviewFixture();
    await fixture.open();
    addTearDown(fixture.dispose);
    await fixture.seedVoice();
    await fixture.seedVoice(id: 'voice-2', messageId: 'message-2');
    for (final owner in [
      voice,
      const PreviewOwner.voiceAttachment('voice-2', messageId: 'message-2'),
    ]) {
      expect(
        await fixture.store.saveTranscript(owner, 'local transcript'),
        isTrue,
      );
      expect(
        await fixture.store.saveTranslation(
          owner,
          'local transcript',
          'en',
          'local translation',
        ),
        isTrue,
      );
    }
    expect(await dbDeleteMessagesForContact(fixture.db, 'contact'), 2);
    expect(await fixture.db.query('local_ai_translations'), isEmpty);
    expect(
      (await fixture.db.query(
        'media_attachments',
      )).map((row) => row['local_transcript']),
      everyElement(isNull),
    );
    expect(await fixture.store.saveTranscript(voice, 'late'), isFalse);
  });

  test(
    'Thought replay preserves cache; edits/deletion and delayed saves cannot reuse it',
    () async {
      final fixture = LocalPreviewFixture();
      await fixture.open();
      addTearDown(fixture.dispose);
      await fixture.db.execute('PRAGMA recursive_triggers = ON');
      await fixture.seedThought();
      expect(
        await fixture.store.saveTranslation(
          thought,
          'أنا في الطريق',
          'en',
          'saved',
        ),
        isTrue,
      );
      await fixture.seedThought();
      expect(
        await fixture.store.loadTranslation(thought, 'أنا في الطريق', 'en'),
        'saved',
      );
      await fixture.seedThought(source: 'different source');
      expect(
        await fixture.store.loadTranslation(thought, 'أنا في الطريق', 'en'),
        isNull,
      );
      expect(
        await fixture.store.saveTranslation(
          thought,
          'أنا في الطريق',
          'en',
          'late',
        ),
        isFalse,
      );
      expect(await fixture.db.query('local_ai_translations'), isEmpty);
      expect(
        await fixture.store.saveTranslation(
          thought,
          'different source',
          'en',
          'new',
        ),
        isTrue,
      );
      await dbDeletePostCascade(fixture.db, 'thought');
      expect(await fixture.db.query('local_ai_translations'), isEmpty);
      expect(
        await fixture.store.saveTranslation(
          thought,
          'different source',
          'en',
          'late',
        ),
        isFalse,
      );
    },
  );

  test(
    'local transcript survives an attachment path move and never enters wire JSON',
    () async {
      final fixture = LocalPreviewFixture();
      await fixture.open();
      addTearDown(fixture.dispose);
      await fixture.seedVoice();
      expect(
        await fixture.store.saveTranscript(voice, 'local-only-result'),
        isTrue,
      );
      await fixture.db.update('media_attachments', {
        'local_path': '/moved/voice.m4a',
      });
      expect(await fixture.store.loadTranscript(voice), 'local-only-result');
      final row = (await fixture.db.query('media_attachments')).single;
      final wire = jsonEncode(MediaAttachment.fromMap(row).toJson());
      expect(wire, isNot(contains('local_transcript')));
      expect(wire, isNot(contains('local-only-result')));
      expect(
        await dbSaveLocalTranscript(
          fixture.db,
          'voice',
          'different-message',
          'stale',
          nowMs: fixture.nowMs,
        ),
        isFalse,
      );
    },
  );
}
