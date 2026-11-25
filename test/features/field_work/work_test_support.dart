import 'dart:typed_data';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_repository.dart';
import 'package:geo_capture/features/field_work/work_storage.dart';
import 'package:geo_capture/core/models/photo_location.dart';

const workId = '11111111-1111-4111-8111-111111111111';
const photoId = '22222222-2222-4222-8222-222222222222';
const versionId = '33333333-3333-4333-8333-333333333333';

WorkPhoto sampleWorkPhoto({
  String id = photoId,
  String role = 'pit',
  bool local = true,
}) => WorkPhoto(
  id: id,
  role: role,
  location: PhotoLocation(
    latitude: 46.777987,
    longitude: 24.309925,
    accuracyMeters: 4.5,
    measuredAt: DateTime.utc(2026, 11, 24, 12, 30),
  ),
  capturedAt: DateTime.utc(2026, 11, 24, 12, 30, 1),
  utcOffsetMinutes: 120,
  locality: 'Sâncraiu',
  county: 'Cluj',
  placeSource: 'manual',
  serialVisible: role == 'old',
  originalMimeType: 'image/png',
  original: local ? Uint8List.fromList([1, 2, 3]) : null,
  stamped: local ? Uint8List.fromList([4, 5, 6]) : null,
);

WorkDocument sampleWorkDocument({
  WorkKind kind = WorkKind.pit,
  bool local = true,
}) => WorkDocument(
  kind: kind,
  oldPole: kind == WorkKind.pit
      ? null
      : const PoleIdentity(serialNumber: '0002610586'),
  newPole: kind == WorkKind.replacement
      ? const PoleIdentity(serialNumber: '0002610587', ntetCode: 'T0PL0138RO')
      : null,
  photos: [
    for (final role in workRoles[kind]!)
      sampleWorkPhoto(
        role: role,
        local: local,
        id: role == workRoles[kind]!.first
            ? photoId
            : '44444444-4444-4444-8444-444444444444',
      ),
  ],
);

class MemoryWorkStore implements WorkDraftStore {
  final drafts = <String, WorkDraft>{};
  bool failWrite = false, failRemove = false;
  @override
  Future<List<WorkDraft>> readAll() async => drafts.values.toList();
  @override
  Future<int> write(WorkDraft draft) async {
    if (failWrite) throw StateError('disk full');
    if ((drafts[draft.id]?.localRevision ?? 0) != draft.localRevision) {
      throw StateError('work_local_conflict');
    }
    final next = draft.localRevision + 1;
    drafts[draft.id] = draft.copyWith(localRevision: next);
    return next;
  }

  @override
  Future<void> remove(WorkDraft draft) async {
    if (failRemove) throw StateError('disk unavailable');
    if (drafts[draft.id]?.localRevision != draft.localRevision) {
      throw StateError('work_local_conflict');
    }
    drafts.remove(draft.id);
  }
}

class FakeWorkRepository implements WorkRepository {
  final sent = <WorkDraft>[];
  Future<WorkDetails> Function(WorkDraft)? onSave;
  WorkSettings current = const WorkSettings(
    allowQrGeneration: false,
    version: versionId,
  );
  @override
  Future<WorkDetails> save(WorkDraft draft) async {
    sent.add(draft);
    return onSave != null
        ? await onSave!(draft)
        : WorkDetails(
      id: draft.id,
      version: versionId,
      revision: draft.expectedVersion == null ? 1 : 2,
      owner: 'worker',
      document: WorkDocument.fromJson(draft.document.toJson()),
    );
  }

  @override
  Future<WorkSettings> settings() async => current;
  @override
  Future<WorkSettings> updateSettings(WorkSettings value, bool enabled) async =>
      current = WorkSettings(allowQrGeneration: enabled, version: versionId);
  @override
  Future<Map<String, dynamic>> list({bool all = false, int page = 1}) async => {
    'items': [],
    'total': 0,
    'page': page,
  };
  @override
  Future<WorkDetails> details(String id) async => WorkDetails(
    id: id,
    version: versionId,
    revision: 1,
    owner: 'worker',
    document: sampleWorkDocument(local: false),
  );
  @override
  Future<List<Map<String, dynamic>>> history(String id) async => [];
  @override
  Future<Uint8List> image(
      String workId,
      String photoId, {
        bool original = false,
      }) async => Uint8List(0);
}