import '../capture/photo_draft.dart';
import '../uploads/upload_batch.dart';

class DraftSnapshot {
  DraftSnapshot({
    required List<PhotoDraft> photos,
    this.oldSerialNumber = '',
    this.newSerialNumber = '',
    this.pendingUploadId,
  }) : photos = List.unmodifiable(photos);

  final List<PhotoDraft> photos;
  final String oldSerialNumber;
  final String newSerialNumber;
  final String? pendingUploadId;

  UploadBatch? get pendingBatch => pendingUploadId == null
      ? null
      : UploadBatch.restore(
    id: pendingUploadId!,
    oldSerialNumber: oldSerialNumber,
    newSerialNumber: newSerialNumber,
    photos: photos,
  );
}

class StoredDrafts {
  const StoredDrafts(this.revision, this.snapshot);
  final int revision;
  final DraftSnapshot snapshot;
}

class DraftStorageException implements Exception {
  const DraftStorageException(this.code);
  final String code;
}

abstract interface class DraftPersistence {
  Future<StoredDrafts> read();
  Future<int> write(DraftSnapshot snapshot, {required int expectedRevision});
}

abstract interface class DraftStorage {
  DraftPersistence forUser(String userId);
}