@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/drafts/draft_snapshot.dart';
import 'package:geo_capture/features/drafts/sembast_draft_storage.dart';
import 'package:geo_capture/features/uploads/upload_batch.dart';
import 'package:sembast_web/sembast_web.dart';

import '../uploads/upload_test_support.dart';

void main() {
  late String name;
  late SembastDraftStorage storage;
  SembastDraftStorage create([String server = 'https://api.example.test']) =>
      SembastDraftStorage(
        server: server,
        openDatabase: () => databaseFactoryWeb.openDatabase(name),
      );
  setUp(() {
    name = 'geocapture_test_${DateTime.now().microsecondsSinceEpoch}';
    storage = create();
  });
  tearDown(() async {
    await storage.close();
    await databaseFactoryWeb.deleteDatabase(name);
  });

  test(
    'IndexedDB preserves image bytes and a frozen batch across reopen',
        () async {
      final batch = UploadBatch.create(
        oldSerialNumber: '0001',
        newSerialNumber: '0002',
        photos: [photo(1)],
        limits: limits,
      );
      await storage
          .forUser('a')
          .write(
        DraftSnapshot(
          photos: batch.photos,
          oldSerialNumber: batch.oldSerialNumber,
          newSerialNumber: batch.newSerialNumber,
          pendingUploadId: batch.id,
        ),
        expectedRevision: 0,
      );
      await storage.close();
      storage = create();
      final restored = (await storage.forUser('a').read()).snapshot;
      expect(
        jsonEncode(restored.pendingBatch!.manifest),
        jsonEncode(batch.manifest),
      );
      expect(
        restored.photos.single.originalBytes,
        batch.photos.single.originalBytes,
      );
      expect(
        restored.photos.single.stamped!.bytes,
        batch.photos.single.stamped!.bytes,
      );
    },
  );

  test('IndexedDB separates accounts and API servers', () async {
    await storage
        .forUser('a')
        .write(DraftSnapshot(photos: [photo(1)]), expectedRevision: 0);
    expect((await storage.forUser('b').read()).snapshot.photos, isEmpty);
    final other = create('https://other.example.test');
    expect((await other.forUser('a').read()).snapshot.photos, isEmpty);
    await other.close();
  });

  test(
    'IndexedDB rejects stale changes without replacing the saved photos',
        () async {
      final account = storage.forUser('a');
      await account.write(
        DraftSnapshot(photos: [photo(1)]),
        expectedRevision: 0,
      );
      await expectLater(
        account.write(DraftSnapshot(photos: [photo(2)]), expectedRevision: 0),
        throwsA(
          isA<DraftStorageException>().having(
                (e) => e.code,
            'code',
            'local_drafts_conflict',
          ),
        ),
      );
      expect((await account.read()).snapshot.photos.single.id, photo(1).id);
    },
  );
}