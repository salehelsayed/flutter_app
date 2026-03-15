import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';

abstract class ContactPresenceSnapshotRepository {
  Stream<ContactPresenceSnapshot> get snapshotChanges;

  Future<ContactPresenceSnapshot?> load(String peerId);

  Future<List<ContactPresenceSnapshot>> loadAll();

  Future<void> save(ContactPresenceSnapshot snapshot);

  void dispose();
}
