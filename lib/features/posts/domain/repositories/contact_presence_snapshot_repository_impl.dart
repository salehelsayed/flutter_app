import 'dart:async';

import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';

class ContactPresenceSnapshotRepositoryImpl
    implements ContactPresenceSnapshotRepository {
  final Future<Map<String, Object?>?> Function(String peerId)
  dbLoadPostLocationPresence;
  final Future<List<Map<String, Object?>>> Function()
  dbLoadAllPostLocationPresence;
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertPostLocationPresence;

  final StreamController<ContactPresenceSnapshot> _snapshotChangesController =
      StreamController<ContactPresenceSnapshot>.broadcast();

  ContactPresenceSnapshotRepositoryImpl({
    required this.dbLoadPostLocationPresence,
    required this.dbLoadAllPostLocationPresence,
    required this.dbUpsertPostLocationPresence,
  });

  @override
  Stream<ContactPresenceSnapshot> get snapshotChanges =>
      _snapshotChangesController.stream;

  @override
  Future<ContactPresenceSnapshot?> load(String peerId) async {
    final row = await dbLoadPostLocationPresence(peerId);
    return row == null ? null : ContactPresenceSnapshot.fromMap(row);
  }

  @override
  Future<List<ContactPresenceSnapshot>> loadAll() async {
    final rows = await dbLoadAllPostLocationPresence();
    return rows.map(ContactPresenceSnapshot.fromMap).toList(growable: false);
  }

  @override
  Future<void> save(ContactPresenceSnapshot snapshot) async {
    await dbUpsertPostLocationPresence(snapshot.toMap());
    _snapshotChangesController.add(snapshot);
  }

  @override
  void dispose() {
    _snapshotChangesController.close();
  }
}
