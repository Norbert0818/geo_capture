import 'dart:convert';

import 'package:geo_capture/core/models/photo_location.dart';
import 'package:geo_capture/features/capture/photo_draft.dart';
import 'package:geo_capture/features/capture/stamped_photo.dart';
import 'package:geo_capture/features/uploads/upload_batch.dart';
import 'package:geo_capture/features/uploads/upload_repository.dart';

const limits = UploadLimits(
  maxPhotos: 10,
  maxSerialNumberLength: 256,
  maxFileBytes: 8 * 1024 * 1024,
  maxBatchBytes: 50 * 1024 * 1024,
);

PhotoDraft photo(int number, {bool prepared = true}) {
  final now = DateTime.utc(2026, 11, 20, 12);
  final location = PhotoLocation(
    latitude: 47.181912 + number / 100,
    longitude: 23.165123,
    accuracyMeters: 5,
    measuredAt: now.subtract(const Duration(seconds: 1)),
  );
  final draft = PhotoDraft(
    id: '11111111-1111-4111-8111-${number.toString().padLeft(12, '0')}',
    originalBytes: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAIAAADkharWAAAAF0lEQVR4nGN0y5vGQApgIkn1qIYRpAEAER0BYmrANbUAAAAASUVORK5CYII=',
    ),
    mimeType: 'image/png',
    capturedAt: now,
    location: location,
  );
  return prepared
      ? draft.withStamp(
    StampedPhoto(
      bytes: base64Decode(
        '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAMABADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDGooor2Dyz/9k=',
      ),
      width: 16,
      height: 12,
      overlayText: location.overlayText,
    ),
  )
      : draft;
}

Map<String, dynamic> receiptJson(UploadBatch batch, {bool replayed = false}) =>
    {
      'id': '22222222-2222-4222-8222-222222222222',
      'clientUploadId': batch.id,
      'serialNumber': batch.serialNumber,
      'uploadedAtUtc': '2026-11-20T12:01:00Z',
      'replayed': replayed,
      'photos': [
        for (final photo in batch.photos) {'clientPhotoId': photo.id},
      ],
    };

UploadReceipt receiptFor(UploadBatch batch, {bool replayed = false}) =>
    UploadReceipt.fromJson(receiptJson(batch, replayed: replayed));

class FakeUploadRepository implements UploadRepository {
  final batches = <UploadBatch>[];
  int limitsCalls = 0;
  Future<UploadReceipt> Function(UploadBatch batch)? onUpload;
  void Function(int, int)? progress;

  @override
  Future<UploadLimits> getLimits() async {
    limitsCalls++;
    return limits;
  }

  @override
  Future<UploadReceipt> upload(
      UploadBatch batch, {
        void Function(int, int)? onProgress,
      }) async {
    batches.add(batch);
    progress = onProgress;
    return onUpload == null ? receiptFor(batch) : await onUpload!(batch);
  }
}