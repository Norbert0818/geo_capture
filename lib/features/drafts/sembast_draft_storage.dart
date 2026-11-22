import 'dart:convert';

import 'package:sembast/sembast.dart';

import '../capture/photo_draft.dart';
import '../uploads/upload_history_models.dart';
import 'draft_codec.dart';
import 'draft_snapshot.dart';
import 'open_draft_database.dart';

class SembastDraftStorage implements DraftStorage {
  SembastDraftStorage({
    required String server,
    Future<Database> Function()? openDatabase,
  }) : _server = _normalizeServer(server),
        _open = openDatabase ?? openDraftDatabase;

  final String _server;
  final Future<Database> Function() _open;
  Future<Database>? _opening;
  final _states = stringMapStoreFactory.store('workspaces_v1');
  final _photos = stringMapStoreFactory.store('photos_v1');

  static String _normalizeServer(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('A plain HTTPS API base URL is required.');
    }
    return uri
        .replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''))
        .toString();
  }

  Future<Database> _database() async {
    try {
      return await (_opening ??= _open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  @override
  DraftPersistence forUser(String userId) {
    if (userId.isEmpty) throw ArgumentError('A signed-in user is required.');
    return _UserDraftPersistence(this, jsonEncode([_server, userId]));
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}

class _UserDraftPersistence implements DraftPersistence {
  const _UserDraftPersistence(this.storage, this.scope);
  final SembastDraftStorage storage;
  final String scope;

  String _photoKey(String id) => jsonEncode([scope, id]);

  int _revision(Map<String, Object?>? value) {
    if (value == null) return 0;
    final revision = value['revision'];
    if (value['schema'] != 1 || revision is! int || revision < 1) {
      throw const DraftStorageException('local_drafts_invalid');
    }
    return revision;
  }

  List<String> _ids(Map<String, Object?> value) {
    final raw = value['photoIds'];
    if (raw is! List ||
        raw.any((id) => id is! String || !isUploadId(id)) ||
        raw.toSet().length != raw.length) {
      throw const FormatException('Invalid draft photo IDs');
    }
    return raw.cast<String>();
  }

  @override
  Future<StoredDrafts> read() async {
    final db = await storage._database();
    try {
      return await db.transaction((transaction) async {
        final record = await storage._states.record(scope).get(transaction);
        final revision = _revision(record);
        if (record == null) return StoredDrafts(0, DraftSnapshot(photos: []));
        final photos = <PhotoDraft>[];
        for (final id in _ids(record)) {
          final raw = await storage._photos
              .record(_photoKey(id))
              .get(transaction);
          if (raw == null || raw['id'] != id) throw const FormatException();
          photos.add(DraftCodec.decodePhoto(raw, scope));
        }
        final pending = record['pendingUploadId'];
        if (pending != null && (pending is! String || !isUploadId(pending))) {
          throw const FormatException();
        }
        final snapshot = DraftSnapshot(
          photos: photos,
          oldSerialNumber: DraftCodec.text(record, 'oldSerialNumber'),
          newSerialNumber: DraftCodec.text(record, 'newSerialNumber'),
          pendingUploadId: pending as String?,
        );
        snapshot.pendingBatch; // Validate frozen data without generating an ID.
        return StoredDrafts(revision, snapshot);
      });
    } on FormatException {
      throw const DraftStorageException('local_drafts_invalid');
    } on ArgumentError {
      throw const DraftStorageException('local_drafts_invalid');
    }
  }

  @override
  Future<int> write(
      DraftSnapshot snapshot, {
        required int expectedRevision,
      }) async {
    final db = await storage._database();
    final ids = snapshot.photos.map((photo) => photo.id).toList();
    if (ids.toSet().length != ids.length || ids.any((id) => !isUploadId(id))) {
      throw const FormatException();
    }
    snapshot.pendingBatch;
    try {
      return await db.transaction((transaction) async {
        final current = await storage._states.record(scope).get(transaction);
        if (_revision(current) != expectedRevision) {
          throw const DraftStorageException('local_drafts_conflict');
        }
        final previousIds = current == null ? <String>[] : _ids(current);
        for (final photo in snapshot.photos) {
          if (!previousIds.contains(photo.id)) {
            final encoded = DraftCodec.encodePhoto(photo, scope);
            DraftCodec.decodePhoto(encoded, scope);
            await storage._photos
                .record(_photoKey(photo.id))
                .put(transaction, encoded);
          }
        }
        for (final id in previousIds.where((id) => !ids.contains(id))) {
          await storage._photos.record(_photoKey(id)).delete(transaction);
        }
        final revision = expectedRevision + 1;
        await storage._states.record(scope).put(transaction, {
          'schema': 1,
          'revision': revision,
          'photoIds': ids,
          'oldSerialNumber': snapshot.oldSerialNumber,
          'newSerialNumber': snapshot.newSerialNumber,
          'pendingUploadId': snapshot.pendingUploadId,
        });
        return revision;
      });
    } on DraftStorageException {
      rethrow;
    } on FormatException {
      rethrow;
    } on ArgumentError {
      rethrow;
    } catch (_) {
      // A filesystem error can leave an uncommitted in-memory cache.
      // Reopen from durable storage before the next read or retry.
      try {
        await storage.close();
      } catch (_) {
        // Keep the original storage error.
      }
      rethrow;
    }
  }
}