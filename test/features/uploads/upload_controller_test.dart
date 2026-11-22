import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/capture/photo_draft_store.dart';
import 'package:geo_capture/features/uploads/upload_batch.dart';
import 'package:geo_capture/features/uploads/upload_controller.dart';

import 'upload_test_support.dart';

void main() {
  late PhotoDraftStore drafts;
  late FakeUploadRepository repository;
  late UploadController controller;

  setUp(() async {
    drafts = PhotoDraftStore();
    repository = FakeUploadRepository();
    controller = UploadController(drafts: drafts, repository: repository);
    await controller.loadLimits();
  });
  tearDown(() {
    controller.dispose();
    drafts.dispose();
  });

  test('100% sent keeps photos until the server confirms saving', () async {
    await drafts.capture(() async => photo(1));
    final result = Completer<UploadReceipt>();
    repository.onUpload = (_) => result.future;
    final pending = controller.submit(
      oldSerialNumber: 'OLD',
      newSerialNumber: '0001',
    );
    repository.progress!(100, 100);
    expect(controller.progress, 1);
    expect(drafts.items, hasLength(1));
    expect(drafts.isLocked, isTrue);
    expect(controller.lastReceipt, isNull);
    result.complete(receiptFor(repository.batches.single));
    await pending;
    expect(drafts.items, isEmpty);
    expect(drafts.isLocked, isFalse);
    expect(controller.lastReceipt!.newSerialNumber, '0001');
  });

  test(
    'lost confirmation preserves the same ID and photos for a safe retry',
        () async {
      await drafts.capture(() async => photo(1));
      repository.onUpload = (_) async =>
      throw const ApiException('service_unavailable');
      await controller.submit(oldSerialNumber: 'OLD', newSerialNumber: '0001');
      final first = controller.pendingBatch;
      expect(drafts.items, hasLength(1));
      expect(drafts.isLocked, isTrue);
      repository.onUpload = (batch) async => receiptFor(batch, replayed: true);
      await controller.submit(
        oldSerialNumber: 'OLD',
        newSerialNumber: 'a different serial must not change a pending batch',
      );
      expect(identical(repository.batches[0], repository.batches[1]), isTrue);
      expect(repository.batches.last.id, first!.id);
      expect(repository.batches.last.newSerialNumber, '0001');
      expect(controller.lastReceipt!.replayed, isTrue);
      expect(drafts.items, isEmpty);
    },
  );

  test('capture and removal cannot change an unconfirmed batch', () async {
    await drafts.capture(() async => photo(1));
    repository.onUpload = (_) async =>
    throw const ApiException('service_unavailable', statusCode: 500);
    await controller.submit(oldSerialNumber: 'OLD', newSerialNumber: 'A');
    var cameraCalled = false;
    await drafts.capture(() async {
      cameraCalled = true;
      return photo(2);
    });
    drafts.remove(photo(1).id);
    expect(cameraCalled, isFalse);
    expect(drafts.items.single.id, photo(1).id);
  });

  test(
    'a definite rejection keeps drafts and enables editing for a new attempt',
        () async {
      await drafts.capture(() async => photo(1));
      repository.onUpload = (_) async =>
      throw const ApiException('invalid_photo_time', statusCode: 400);
      await controller.submit(oldSerialNumber: 'OLD', newSerialNumber: 'A');
      expect(controller.pendingBatch, isNull);
      expect(controller.errorCode, 'invalid_photo_time');
      expect(drafts.isLocked, isFalse);
      drafts.remove(photo(1).id);
      await drafts.capture(() async => photo(2));
      repository.onUpload = (batch) async => receiptFor(batch);
      await controller.submit(oldSerialNumber: 'OLD', newSerialNumber: 'B');
      expect(repository.batches[0].id, isNot(repository.batches[1].id));
      expect(controller.lastReceipt!.newSerialNumber, 'B');
    },
  );

  test('double submission produces only one in-flight request', () async {
    await drafts.capture(() async => photo(1));
    final result = Completer<UploadReceipt>();
    repository.onUpload = (_) => result.future;
    final first = controller.submit(
      oldSerialNumber: 'OLD',
      newSerialNumber: 'A',
    );
    await controller.submit(oldSerialNumber: 'OLD', newSerialNumber: 'A');
    expect(repository.batches, hasLength(1));
    result.complete(receiptFor(repository.batches.single));
    await first;
  });

  test(
    'empty serial and unfinished image are rejected before HTTP submission',
        () async {
      await drafts.capture(() async => photo(1, prepared: false));
      await controller.submit(oldSerialNumber: 'OLD', newSerialNumber: '   ');
      expect(controller.errorCode, 'invalid_new_serial_number');
      await controller.submit(oldSerialNumber: 'OLD', newSerialNumber: 'A');
      expect(controller.errorCode, 'photo_not_ready');
      expect(repository.batches, isEmpty);
      expect(drafts.items, hasLength(1));
      expect(drafts.isLocked, isFalse);
    },
  );

  test('applies the current server photo limit before submission', () async {
    controller.limits = const UploadLimits(
      maxPhotos: 1,
      maxSerialNumberLength: 5,
      maxFileBytes: 10000,
      maxBatchBytes: 20000,
    );
    await drafts.capture(() async => photo(1));
    await drafts.capture(() async => photo(2));
    await controller.submit(oldSerialNumber: 'OLD', newSerialNumber: 'A');
    expect(controller.errorCode, 'too_many_photos');
    expect(repository.batches, isEmpty);
  });

  test('rejects a batch whose combined file sizes exceed the limit', () async {
    await drafts.capture(() async => photo(1));
    final p = photo(1);
    controller.limits = UploadLimits(
      maxPhotos: 10,
      maxSerialNumberLength: 256,
      maxFileBytes: 10000,
      maxBatchBytes: p.originalBytes.length + p.stamped!.bytes.length - 1,
    );
    await controller.submit(oldSerialNumber: 'OLD', newSerialNumber: 'A');
    expect(controller.errorCode, 'upload_too_large');
    expect(repository.batches, isEmpty);
    expect(drafts.items, hasLength(1));
  });

  test('a mismatched server confirmation does not erase photos', () async {
    await drafts.capture(() async => photo(1));
    repository.onUpload = (batch) async => UploadReceipt.fromJson(
      receiptJson(batch)..['newSerialNumber'] = 'wrong',
    );
    await controller.submit(oldSerialNumber: 'OLD', newSerialNumber: 'A');
    expect(controller.errorCode, 'service_unavailable');
    expect(controller.pendingBatch, isNotNull);
    expect(drafts.items, hasLength(1));
  });
}