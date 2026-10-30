// ignore_for_file: file_names

import 'package:flutter_app/core/database/migrations/125_local_ai_previews.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../features/translate_preview/local_preview_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  for (final upgrade in [false, true]) {
    test(
      'local previews ${upgrade ? 'upgrade v124' : 'fresh install'}',
      () async {
        final fixture = LocalPreviewFixture();
        await fixture.open(version: upgrade ? 124 : 125);
        addTearDown(fixture.dispose);
        await fixture.seedVoice();
        await fixture.seedThought();
        if (upgrade) {
          await fixture.db.close();
          await fixture.open(version: 125);
        }
        expect(await fixture.db.getVersion(), 125);
        final attachment = (await fixture.db.query('media_attachments')).single;
        expect(attachment['id'], 'voice');
        expect(attachment.containsKey('local_transcript'), isTrue);
        expect(attachment['local_transcript'], isNull);
        expect((await fixture.db.query('posts')).single['post_id'], 'thought');
        expect(await fixture.db.query('local_ai_translations'), isEmpty);

        const owner = PreviewOwner.voiceAttachment(
          'voice',
          messageId: 'message',
        );
        expect(
          await fixture.store.saveTranscript(owner, 'preserved transcript'),
          isTrue,
        );
        expect(
          await fixture.store.saveTranslation(
            owner,
            'preserved transcript',
            'en',
            'preserved translation',
          ),
          isTrue,
        );
        await runLocalAiPreviewsMigration(fixture.db);
        await runLocalAiPreviewsMigration(fixture.db);
        expect(
          (await fixture.db.query('media_attachments')).single['id'],
          'voice',
        );
        expect(
          await fixture.store.loadTranscript(owner),
          'preserved transcript',
        );
        expect(
          await fixture.store.loadTranslation(
            owner,
            'preserved transcript',
            'en',
          ),
          'preserved translation',
        );
      },
    );
  }
}
