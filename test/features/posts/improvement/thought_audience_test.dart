import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_retract_envelope.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

ContactModel _friend(String peerId) => ContactModel(
  peerId: peerId,
  publicKey: 'pk-$peerId',
  rendezvous: 'rendezvous',
  username: peerId,
  signature: 'signature',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-$peerId',
);

void main() {
  late InMemoryPostRepository posts;
  late InMemoryContactRepository contacts;

  setUp(() {
    posts = InMemoryPostRepository();
    contacts = InMemoryContactRepository();
    for (final peerId in ['layla', 'omar', 'nour']) {
      contacts.addTestContact(_friend(peerId));
    }
  });

  Future<String> share(PostAudience audience, String text) async {
    final (result, created) = await createLocalPost(
      postRepo: posts,
      contactRepo: contacts,
      senderPeerId: 'me',
      senderUsername: 'me',
      text: text,
      audience: audience,
      mediaFileManager: FakeMediaFileManager(),
    );
    expect(result, SendPostResult.success);
    return created!.post.id;
  }

  Future<Map<String, Set<String>>> retractsByPost() async => {
    for (final job in await posts.loadRetryableFollowOnOutboxJobs())
      if (job.event.eventType == PostRetractEnvelope.type)
        job.event.postId: {
          for (final delivery in job.recipientDeliveries)
            delivery.recipientPeerId,
        },
  };

  test('a thought for picked people asks the friends it leaves out to drop '
      'the thought it replaces', () async {
    final old = await share(PostAudience.allFriends(), 'for everyone');
    final picked = await share(PostAudience.pickPeople(['layla']), 'for one');

    expect(await posts.getPost(old), isNull);
    expect(await posts.getPost(picked), isNotNull);
    expect(await retractsByPost(), {
      old: {'omar', 'nour'},
    });
  });

  test('a thought for everyone sends no drop: it replaces the old one on '
      'arrival', () async {
    await share(PostAudience.pickPeople(['layla']), 'for one');
    await share(PostAudience.allFriends(), 'for everyone');

    expect(await retractsByPost(), isEmpty);
  });
}
