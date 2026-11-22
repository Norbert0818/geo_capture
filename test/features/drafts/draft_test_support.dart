import 'dart:async';

import 'package:geo_capture/features/drafts/draft_snapshot.dart';

class TestDraftStorage implements DraftStorage {
  final users = <String, TestDraftDisk>{};
  @override
  TestDraftDisk forUser(String userId) =>
      users.putIfAbsent(userId, TestDraftDisk.new);
}

class TestDraftDisk implements DraftPersistence {
  StoredDrafts saved = StoredDrafts(0, DraftSnapshot(photos: []));
  int writes = 0;
  bool failReads = false;
  bool failWrites = false;
  bool failCleanup = false;
  bool invalid = false;
  Future<void> Function(DraftSnapshot)? beforeWrite;

  @override
  Future<StoredDrafts> read() async {
    if (failReads) throw StateError('Read failed');
    if (invalid) throw const DraftStorageException('local_drafts_invalid');
    return saved;
  }

  @override
  Future<int> write(
      DraftSnapshot snapshot, {
        required int expectedRevision,
      }) async {
    writes++;
    await beforeWrite?.call(snapshot);
    if (failWrites || (failCleanup && snapshot.photos.isEmpty)) {
      throw StateError('Storage full');
    }
    if (saved.revision != expectedRevision) {
      throw const DraftStorageException('local_drafts_conflict');
    }
    saved = StoredDrafts(expectedRevision + 1, snapshot);
    return saved.revision;
  }
}