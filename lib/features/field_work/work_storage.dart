import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/blob.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';

import 'work_models.dart';

abstract interface class WorkDraftStore {
  Future<List<WorkDraft>> readAll();
  Future<int> write(WorkDraft draft);
  Future<void> remove(WorkDraft draft);
}

class SembastWorkStorage {
  SembastWorkStorage({
    required String server,
    Future<Database> Function()? openDatabase,
  }) : _server = Uri.parse(server).toString().replaceFirst(RegExp(r'/+$'), ''),
       _open = openDatabase ?? _openWorkDatabase;
  final String _server;
  final Future<Database> Function() _open;
  Future<Database>? _opening;
  Future<Database> database() async {
    try {
      return await (_opening ??= _open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  WorkDraftStore forUser(String id) {
    if (id.isEmpty || Uri.parse(_server).scheme != 'https') {
      throw ArgumentError('A signed-in HTTPS scope is required.');
    }
    return _UserWorkStore(this, jsonEncode([_server, id]));
  }
}

Future<Database> _openWorkDatabase() async {
  if (kIsWeb) {
    return databaseFactoryWeb.openDatabase('geocapture_field_work_v1');
  }
  final folder = await getApplicationSupportDirectory();
  await folder.create(recursive: true);
  return databaseFactoryIo.openDatabase(
    '${folder.path}/geocapture_field_work_v1.db',
  );
}

class _UserWorkStore implements WorkDraftStore {
  _UserWorkStore(this.storage, this.scope);
  final SembastWorkStorage storage;
  final String scope;
  final states = stringMapStoreFactory.store('work_drafts');
  final photos = stringMapStoreFactory.store('work_photos');
  String key(String id) => jsonEncode([scope, id]);
  String photoKey(String workId, String photoId) =>
      jsonEncode([scope, workId, photoId]);

  @override
  Future<List<WorkDraft>> readAll() async {
    final db = await storage.database();
    return db.transaction((transaction) async {
      final rows = await states.find(
        transaction,
        finder: Finder(filter: Filter.equals('scope', scope)),
      );
      final result = <WorkDraft>[];
      for (final row in rows) {
        final data = row.value;
        if (data['schema'] != 1) throw StateError('work_local_invalid');
        final document = WorkDocument.fromJson(
          jsonDecode(data['document'] as String) as Map<String, dynamic>,
        );
        final localIds = (data['localPhotoIds'] as List).cast<String>().toSet();
        final hydrated = <WorkPhoto>[];
        for (final photo in document.photos) {
          final bytes = await photos
              .record(photoKey(data['id'] as String, photo.id))
              .get(transaction);
          if (bytes == null) {
            if (localIds.contains(photo.id)) {
              throw StateError('work_local_invalid');
            }
            hydrated.add(photo);
            continue;
          }
          if (bytes['scope'] != scope ||
              bytes['workId'] != data['id'] ||
              bytes['original'] is! Blob ||
              bytes['stamped'] is! Blob) {
            throw StateError('work_local_invalid');
          }
          hydrated.add(
            photo.withBytes(
              Uint8List.fromList((bytes['original'] as Blob).bytes),
              Uint8List.fromList((bytes['stamped'] as Blob).bytes),
            ),
          );
        }
        result.add(
          WorkDraft(
            id: data['id'] as String,
            document: document.copyWith(photos: hydrated),
            expectedVersion: data['expectedVersion'] as String?,
            pendingChangeId: data['pendingChangeId'] as String?,
            reason: data['reason'] as String,
            localRevision: data['revision'] as int,
          ),
        );
      }
      return result;
    });
  }

  @override
  Future<int> write(WorkDraft draft) async {
    final db = await storage.database();
    return db.transaction((transaction) async {
      final record = states.record(key(draft.id));
      final current = await record.get(transaction);
      if ((current?['revision'] ?? 0) != draft.localRevision) {
        throw StateError('work_local_conflict');
      }
      final oldIds = current == null
          ? <String>[]
          : WorkDocument.fromJson(
              jsonDecode(current['document'] as String) as Map<String, dynamic>,
            ).photos.map((p) => p.id).toList();
      for (final photo in draft.document.photos.where(
        (photo) => photo.isLocal,
      )) {
        if (!oldIds.contains(photo.id)) {
          await photos.record(photoKey(draft.id, photo.id)).put(transaction, {
            'scope': scope,
            'workId': draft.id,
            'original': Blob(photo.original!),
            'stamped': Blob(photo.stamped!),
          });
        }
      }
      final ids = draft.document.photos.map((p) => p.id).toSet();
      for (final id in oldIds.where((id) => !ids.contains(id))) {
        await photos.record(photoKey(draft.id, id)).delete(transaction);
      }
      final revision = draft.localRevision + 1;
      await record.put(transaction, {
        'scope': scope,
        'schema': 1,
        'id': draft.id,
        'document': jsonEncode(draft.document.toJson()),
        'expectedVersion': draft.expectedVersion,
        'localPhotoIds': draft.document.photos
            .where((photo) => photo.isLocal)
            .map((photo) => photo.id)
            .toList(),
        'pendingChangeId': draft.pendingChangeId,
        'reason': draft.reason,
        'revision': revision,
      });
      return revision;
    });
  }

  @override
  Future<void> remove(WorkDraft draft) async {
    final db = await storage.database();
    await db.transaction((transaction) async {
      final record = states.record(key(draft.id));
      final current = await record.get(transaction);
      if ((current?['revision'] ?? 0) != draft.localRevision) {
        throw StateError('work_local_conflict');
      }
      for (final photo in draft.document.photos) {
        await photos.record(photoKey(draft.id, photo.id)).delete(transaction);
      }
      await record.delete(transaction);
    });
  }
}