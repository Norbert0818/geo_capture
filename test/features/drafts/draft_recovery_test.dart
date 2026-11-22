import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/capture/photo_draft_store.dart';
import 'package:geo_capture/features/uploads/upload_batch.dart';
import 'package:geo_capture/features/uploads/upload_controller.dart';

import '../uploads/upload_test_support.dart';
import 'draft_test_support.dart';

void main() {
  late TestDraftDisk disk;
  late PhotoDraftStore drafts;
  late FakeUploadRepository repository;
  late UploadController uploads;

  Future<void> restart() async {
    uploads.dispose();
    drafts.dispose();
    drafts = PhotoDraftStore(persistence: disk);
    uploads = UploadController(drafts: drafts, repository: repository);
    await drafts.restore();
  }

  setUp(() async {
    disk = TestDraftDisk();
    drafts = PhotoDraftStore(persistence: disk);
    repository = FakeUploadRepository();
    uploads = UploadController(drafts: drafts, repository: repository);
    await drafts.restore();
    await uploads.loadLimits();
  });
  tearDown(() {
    uploads.dispose();
    drafts.dispose();
  });

  test('photos, both variants, GPS, timestamps and unfinished serials survive restart', () async {
    await drafts.capture(() async => photo(1));
    await drafts.capture(() async => photo(2));
    await drafts.rememberSerials('  OLD-0001 ', 'NEW-0002');
    await restart();
    expect(drafts.items.map((p) => p.id), [photo(1).id, photo(2).id]);
    expect(drafts.items.first.originalBytes, photo(1).originalBytes);
    expect(drafts.items.first.stamped!.bytes, photo(1).stamped!.bytes);
    expect(
      drafts.items.first.location.overlayText,
      photo(1).location.overlayText,
    );
    expect(
      drafts.items.first.location.accuracyMeters,
      photo(1).location.accuracyMeters,
    );
    expect(
      drafts.items.first.location.measuredAtUtc,
      photo(1).location.measuredAtUtc,
    );
    expect(drafts.items.first.capturedAtUtc, photo(1).capturedAtUtc);
    expect(drafts.oldSerialNumber, '  OLD-0001 ');
    expect(drafts.newSerialNumber, 'NEW-0002');
    expect(drafts.pendingBatch, isNull);
  });

  test('deleting one photo is durable and preserves the other photo', () async {
    await drafts.capture(() async => photo(1));
    await drafts.capture(() async => photo(2));
    await drafts.remove(photo(1).id);
    await restart();
    expect(drafts.items.single.id, photo(2).id);
  });

  test('the batch ID is durable before any HTTP request starts', () async {
    await drafts.capture(() async => photo(1));
    repository.onUpload = (batch) async {
      expect(disk.saved.snapshot.pendingUploadId, batch.id);
      expect(disk.saved.snapshot.oldSerialNumber, '0001');
      expect(disk.saved.snapshot.newSerialNumber, '0002');
      expect(
        disk.saved.snapshot.photos.single.originalBytes,
        batch.photos.single.originalBytes,
      );
      return receiptFor(batch);
    };
    await uploads.submit(oldSerialNumber: '0001', newSerialNumber: '0002');
    expect(uploads.lastReceipt, isNotNull);
  });

  test('server saved but response lost: restart retries exactly the same payload once', () async {
    await drafts.capture(() async => photo(1));
    await drafts.capture(() async => photo(2));
    String? savedManifest;
    var serverRows = 0;
    repository.onUpload = (batch) async {
      final manifest = jsonEncode(batch.manifest);
      if (savedManifest == null) {
        savedManifest = manifest;
        serverRows++;
        throw const ApiException('service_unavailable');
      }
      expect(manifest, savedManifest);
      return receiptFor(batch, replayed: true);
    };
    await uploads.submit(oldSerialNumber: '0001', newSerialNumber: '0002');
    final first = uploads.pendingBatch!;
    await restart();
    expect(drafts.isLocked, isTrue);
    expect(uploads.pendingBatch!.id, first.id);
    // A frozen retry does not depend on fetching fresh limits.
    expect(uploads.limits, isNull);
    await uploads.submit(
      oldSerialNumber: 'IGNORED',
      newSerialNumber: 'IGNORED',
    );
    expect(serverRows, 1);
    expect(uploads.lastReceipt!.replayed, isTrue);
    expect(disk.saved.snapshot.photos, isEmpty);
    await restart();
    expect(drafts.items, isEmpty);
    expect(uploads.pendingBatch, isNull);
  });

  test(
    'a failed batch save never starts HTTP and retains the ID for retry',
        () async {
      await drafts.capture(() async => photo(1));
      disk.failWrites = true;
      await uploads.submit(oldSerialNumber: 'OLD', newSerialNumber: 'NEW');
      final id = uploads.pendingBatch!.id;
      expect(repository.batches, isEmpty);
      expect(drafts.items, hasLength(1));
      expect(drafts.hasUnsavedChanges, isTrue);
      disk.failWrites = false;
      expect(await drafts.flush(), isTrue);
      await uploads.submit(
        oldSerialNumber: 'CHANGED',
        newSerialNumber: 'CHANGED',
      );
      expect(repository.batches.single.id, id);
      expect(repository.batches.single.oldSerialNumber, 'OLD');
    },
  );

  test('failed local cleanup after server confirmation preserves a replayable batch', () async {
    await drafts.capture(() async => photo(1));
    disk.failCleanup = true;
    await uploads.submit(oldSerialNumber: 'OLD', newSerialNumber: 'NEW');
    final id = uploads.pendingBatch!.id;
    expect(drafts.items, hasLength(1));
    expect(disk.saved.snapshot.pendingUploadId, id);
    expect(uploads.lastReceipt, isNull);
    disk.failCleanup = false;
    await restart();
    repository.onUpload = (batch) async => receiptFor(batch, replayed: true);
    await uploads.submit(oldSerialNumber: '', newSerialNumber: '');
    expect(repository.batches.last.id, id);
    expect(drafts.items, isEmpty);
    expect(uploads.lastReceipt!.replayed, isTrue);
  });

  test('an incorrect receipt never deletes the local photos', () async {
    await drafts.capture(() async => photo(1));
    repository.onUpload = (batch) async => UploadReceipt.fromJson(
      receiptJson(batch)..['oldSerialNumber'] = 'OTHER',
    );
    await uploads.submit(oldSerialNumber: 'OLD', newSerialNumber: 'NEW');
    await restart();
    expect(drafts.items, hasLength(1));
    expect(uploads.pendingBatch, isNotNull);
  });

  test('definite rejection clears the frozen ID durably but keeps photos and serials', () async {
    await drafts.capture(() async => photo(1));
    repository.onUpload = (_) async =>
    throw const ApiException('invalid_photo_time', statusCode: 400);
    await uploads.submit(oldSerialNumber: 'OLD', newSerialNumber: 'NEW');
    await restart();
    expect(uploads.pendingBatch, isNull);
    expect(drafts.isLocked, isFalse);
    expect(drafts.items, hasLength(1));
    expect(drafts.oldSerialNumber, 'OLD');
    expect(drafts.newSerialNumber, 'NEW');
  });

  test(
    'read failure blocks capture and upload without overwriting saved data',
        () async {
      await drafts.capture(() async => photo(1));
      final writes = disk.writes;
      disk.failReads = true;
      await restart();
      var captured = false;
      await drafts.capture(() async {
        captured = true;
        return photo(2);
      });
      await uploads.submit(oldSerialNumber: 'A', newSerialNumber: 'B');
      expect(captured, isFalse);
      expect(repository.batches, isEmpty);
      expect(disk.writes, writes);
      expect(disk.saved.snapshot.photos, hasLength(1));
      disk.failReads = false;
      await drafts.restore();
      expect(drafts.items.single.id, photo(1).id);
    },
  );

  test(
    'invalid saved data is preserved and is not treated as an empty workspace',
        () async {
      disk.invalid = true;
      await restart();
      expect(drafts.isReady, isFalse);
      expect(drafts.storageErrorCode, 'local_drafts_invalid');
      expect(await drafts.flush(), isFalse);
      expect(disk.writes, 0);
    },
  );

  test(
    'storage-full error keeps the captured photo in memory and supports retry',
        () async {
      disk.failWrites = true;
      await drafts.capture(() async => photo(1));
      expect(drafts.items, hasLength(1));
      expect(drafts.hasUnsavedChanges, isTrue);
      expect(drafts.storageErrorCode, 'local_drafts_write_failed');
      var extraCapture = false;
      await drafts.capture(() async {
        extraCapture = true;
        return photo(2);
      });
      expect(extraCapture, isFalse);
      disk.failWrites = false;
      expect(await drafts.flush(), isTrue);
      await restart();
      expect(drafts.items.single.id, photo(1).id);
    },
  );

  test(
    'typing during a write eventually saves the latest serial values',
        () async {
      await drafts.capture(() async => photo(1));
      final gate = Completer<void>();
      var first = true;
      disk.beforeWrite = (_) async {
        if (first) {
          first = false;
          await gate.future;
        }
      };
      final one = drafts.rememberSerials('OLD-1', 'NEW-1');
      final two = drafts.rememberSerials('OLD-2', 'NEW-2');
      gate.complete();
      await Future.wait([one, two]);
      await restart();
      expect(drafts.oldSerialNumber, 'OLD-2');
      expect(drafts.newSerialNumber, 'NEW-2');
    },
  );

  test('a restored unconfirmed batch blocks capture and deletion', () async {
    await drafts.capture(() async => photo(1));
    repository.onUpload = (_) async =>
    throw const ApiException('service_unavailable');
    await uploads.submit(oldSerialNumber: 'OLD', newSerialNumber: 'NEW');
    await restart();
    await drafts.remove(photo(1).id);
    await drafts.capture(() async => photo(2));
    expect(drafts.items.single.id, photo(1).id);
  });

  test('disposing during a queued save still commits the latest already-entered data', () async {
    await drafts.capture(() async => photo(1));
    final gate = Completer<void>();
    var first = true;
    disk.beforeWrite = (_) async {
      if (first) {
        first = false;
        await gate.future;
      }
    };
    final one = drafts.rememberSerials('OLD-1', 'NEW-1');
    final two = drafts.rememberSerials('OLD-2', 'NEW-2');
    uploads.dispose();
    drafts.dispose();
    gate.complete();
    await Future.wait([one, two]);
    drafts = PhotoDraftStore(persistence: disk);
    uploads = UploadController(drafts: drafts, repository: repository);
    await drafts.restore();
    expect(drafts.items.single.id, photo(1).id);
    expect(drafts.oldSerialNumber, 'OLD-2');
    expect(drafts.newSerialNumber, 'NEW-2');
  });

  test('disposing during an HTTP request preserves the frozen batch for next login', () async {
    await drafts.capture(() async => photo(1));
    final started = Completer<UploadBatch>();
    final response = Completer<UploadReceipt>();
    repository.onUpload = (batch) {
      started.complete(batch);
      return response.future;
    };
    final sending = uploads.submit(
      oldSerialNumber: 'OLD',
      newSerialNumber: 'NEW',
    );
    final batch = await started.future;
    await restart();
    response.complete(receiptFor(batch));
    await sending;
    expect(drafts.items.single.id, photo(1).id);
    expect(uploads.pendingBatch!.id, batch.id);
    expect(disk.saved.snapshot.pendingUploadId, batch.id);
  });
}