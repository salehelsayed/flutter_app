import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a finished media download reports its post as changed', () async {
    final updates = <(String, String)>[];
    final repository = PostRepositoryImpl(
      dbInsertPost: (_) async => throw UnimplementedError(),
      dbLoadPost: (_) async => throw UnimplementedError(),
      dbLoadPostsFeed: () async => throw UnimplementedError(),
      dbUpsertRecipientDelivery: (_) async => throw UnimplementedError(),
      dbLoadRecipientDeliveries: (_) async => throw UnimplementedError(),
      dbMarkPostFocused: (_) async => throw UnimplementedError(),
      dbUpdatePostMediaLocalPath: (mediaId, localPath) async =>
          updates.add((mediaId, localPath)),
    );
    addTearDown(repository.dispose);
    final changed = repository.postChanges.first.timeout(
      const Duration(seconds: 1),
    );

    await repository.updatePostMediaLocalPath(
      'media-lake',
      'post_media/lake.png',
      postId: 'lake',
    );

    expect(updates, [('media-lake', 'post_media/lake.png')]);
    expect(await changed, 'lake');
  });
}
