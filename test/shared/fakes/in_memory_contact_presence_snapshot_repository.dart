import 'dart:async';

import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';

class InMemoryContactPresenceSnapshotRepository
    implements ContactPresenceSnapshotRepository {
  final Map<String, ContactPresenceSnapshot> _snapshots =
      <String, ContactPresenceSnapshot>{};
  final StreamController<ContactPresenceSnapshot> _changes =
      StreamController<ContactPresenceSnapshot>.broadcast();

  InMemoryContactPresenceSnapshotRepository({
    Iterable<ContactPresenceSnapshot> initialSnapshots =
        const <ContactPresenceSnapshot>[],
  }) {
    for (final snapshot in initialSnapshots) {
      _snapshots[snapshot.peerId] = snapshot;
    }
  }

  @override
  Stream<ContactPresenceSnapshot> get snapshotChanges => _changes.stream;

  @override
  Future<ContactPresenceSnapshot?> load(String peerId) async {
    return _snapshots[peerId];
  }

  @override
  Future<List<ContactPresenceSnapshot>> loadAll() async {
    return _snapshots.values.toList(growable: false);
  }

  @override
  Future<void> save(ContactPresenceSnapshot snapshot) async {
    _snapshots[snapshot.peerId] = snapshot;
    _changes.add(snapshot);
  }

  @override
  void dispose() {
    _changes.close();
  }
}
