@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/capture/photo_draft.dart';
import 'package:geo_capture/features/drafts/draft_snapshot.dart';
import 'package:geo_capture/features/drafts/sembast_draft_storage.dart';
import 'package:geo_capture/features/uploads/upload_batch.dart';
import 'package:sembast/sembast_io.dart';

import '../uploads/upload_test_support.dart';

class _FailingCommitDatabase implements Database {
  _FailingCommitDatabase(this.inner);
  final Database inner;
  bool closed = false;

  @override
  Future<T> transaction<T>(FutureOr<T> Function(Transaction) action) async {
    await inner.transaction(action);
    throw StateError('Storage completion failed');
  }

  @override
  Future<void> close() async {
    closed = true;
    await inner.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late Directory folder;
  late String path;
  late SembastDraftStorage storage;
  SembastDraftStorage create([String server = 'https://api.example.test']) =>
      SembastDraftStorage(
        server: server,
        openDatabase: () => databaseFactoryIo.openDatabase(path),
      );
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('geocapture_drafts_');
    path = '${folder.path}/drafts.db';
    storage = create();
  });
  tearDown(() async {
    await storage.close();
    await folder.delete(recursive: true);
  });

  test(
    'real file survives close and reopen with exact photos and frozen manifest',
        () async {
      final batch = UploadBatch.create(
        oldSerialNumber: '0001',
        newSerialNumber: '0002',
        photos: [photo(2), photo(1)],
        limits: limits,
      );
      final saved = DraftSnapshot(
        photos: batch.photos,
        oldSerialNumber: batch.oldSerialNumber,
        newSerialNumber: batch.newSerialNumber,
        pendingUploadId: batch.id,
      );
      await storage.forUser('user-a').write(saved, expectedRevision: 0);
      await storage.close();
      storage = create();
      final restored = (await storage.forUser('user-a').read()).snapshot;
      expect(
        jsonEncode(restored.pendingBatch!.manifest),
        jsonEncode(batch.manifest),
      );
      for (var i = 0; i < batch.photos.length; i++) {
        expect(restored.photos[i].originalBytes, batch.photos[i].originalBytes);
        expect(
          restored.photos[i].stamped!.bytes,
          batch.photos[i].stamped!.bytes,
        );
        expect(
          restored.photos[i].stamped!.width,
          batch.photos[i].stamped!.width,
        );
        expect(
          restored.photos[i].stamped!.height,
          batch.photos[i].stamped!.height,
        );
      }
      expect(await File(path).length(), greaterThan(0));
    },
  );

  test('accounts and API servers use separate workspaces', () async {
    await storage
        .forUser('a')
        .write(DraftSnapshot(photos: [photo(1)]), expectedRevision: 0);
    expect((await storage.forUser('b').read()).snapshot.photos, isEmpty);
    final other = create('https://other.example.test');
    expect((await other.forUser('a').read()).snapshot.photos, isEmpty);
    await other.close();
  });

  test('deletion removes only the current account records', () async {
    await storage
        .forUser('a')
        .write(DraftSnapshot(photos: [photo(1)]), expectedRevision: 0);
    await storage
        .forUser('b')
        .write(DraftSnapshot(photos: [photo(2)]), expectedRevision: 0);
    await storage
        .forUser('a')
        .write(DraftSnapshot(photos: []), expectedRevision: 1);
    expect((await storage.forUser('a').read()).snapshot.photos, isEmpty);
    expect(
      (await storage.forUser('b').read()).snapshot.photos.single.id,
      photo(2).id,
    );
  });

  test(
    'a stale writer cannot overwrite a newer draft or create orphan photos',
        () async {
      final account = storage.forUser('a');
      final initial = await account.read();
      await account.write(
        DraftSnapshot(photos: [photo(1)]),
        expectedRevision: initial.revision,
      );
      await expectLater(
        account.write(
          DraftSnapshot(photos: [photo(2)]),
          expectedRevision: initial.revision,
        ),
        throwsA(
          isA<DraftStorageException>().having(
                (e) => e.code,
            'code',
            'local_drafts_conflict',
          ),
        ),
      );
      expect((await account.read()).snapshot.photos.single.id, photo(1).id);
      final db = await databaseFactoryIo.openDatabase(path);
      expect(await stringMapStoreFactory.store('photos_v1').count(db), 1);
    },
  );

  test('an invalid photo rolls back the entire local transaction', () async {
    final account = storage.forUser('a');
    await account.write(DraftSnapshot(photos: [photo(1)]), expectedRevision: 0);
    final good = photo(2);
    final invalid = PhotoDraft(
      id: photo(3).id,
      originalBytes: good.originalBytes,
      mimeType: 'unsupported',
      capturedAt: good.capturedAtUtc,
      location: good.location,
    );
    await expectLater(
      account.write(
        DraftSnapshot(photos: [good, invalid]),
        expectedRevision: 1,
      ),
      throwsFormatException,
    );
    expect((await account.read()).snapshot.photos.single.id, photo(1).id);
    final db = await databaseFactoryIo.openDatabase(path);
    expect(await stringMapStoreFactory.store('photos_v1').count(db), 1);
  });

  test(
    'future schema versions fail without clearing any saved records',
        () async {
      final account = storage.forUser('a');
      await account.write(
        DraftSnapshot(photos: [photo(1)]),
        expectedRevision: 0,
      );
      final db = await databaseFactoryIo.openDatabase(path);
      final states = stringMapStoreFactory.store('workspaces_v1');
      final row = (await states.find(db)).single;
      await states.record(row.key).update(db, {'schema': 999});
      await expectLater(account.read(), throwsA(isA<DraftStorageException>()));
      expect(await stringMapStoreFactory.store('photos_v1').count(db), 1);
      expect((await states.record(row.key).get(db))!['schema'], 999);
    },
  );

  test(
    'unexpected commit errors invalidate the cache and reopen the durable data',
        () async {
      final failing = _FailingCommitDatabase(
        await databaseFactoryIo.openDatabase(path),
      );
      var opens = 0;
      storage = SembastDraftStorage(
        server: 'https://api.example.test',
        openDatabase: () async {
          opens++;
          return opens == 1
              ? failing
              : await databaseFactoryIo.openDatabase(path);
        },
      );
      await expectLater(
        storage
            .forUser('a')
            .write(DraftSnapshot(photos: [photo(1)]), expectedRevision: 0),
        throwsStateError,
      );
      expect(failing.closed, isTrue);
      final restored = await storage.forUser('a').read();
      expect(opens, 2);
      expect(restored.snapshot.photos.single.id, photo(1).id);
      expect(restored.revision, 1);
    },
  );
}