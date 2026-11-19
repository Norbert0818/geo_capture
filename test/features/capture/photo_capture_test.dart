import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/models/photo_location.dart';
import 'package:geo_capture/features/capture/photo_capture_service.dart';
import 'package:geo_capture/features/capture/photo_draft.dart';
import 'package:geo_capture/features/capture/photo_draft_store.dart';

final now = DateTime.utc(2026, 11, 19, 12);
Uint8List jpegBytes() => Uint8List.fromList([0xff, 0xd8, 0xff, 0x01]);

PhotoLocation location({
  double latitude = 47.181912,
  double longitude = 23.165123,
  DateTime? measuredAt,
}) {
  return PhotoLocation(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: 6,
    measuredAt: measuredAt ?? now,
  );
}

PhotoDraft draft(String id, {double latitude = 47.181912}) {
  return PhotoDraft(
    id: id,
    originalBytes: jpegBytes(),
    mimeType: 'image/jpeg',
    capturedAt: now,
    location: location(latitude: latitude),
  );
}

void main() {
  test('each photo receives its own fresh location before capture', () async {
    final events = <String>[];
    final fixes = [
      location(),
      location(
        latitude: 47.181999,
        measuredAt: now.add(const Duration(seconds: 1)),
      ),
    ];
    var index = 0;

    final capture = PhotoCaptureService(
      readLocation: () async {
        events.add('location');
        return fixes[index++];
      },
      clock: () => now.add(Duration(seconds: index)),
      newId: () => index.toString(),
    );

    Future<Uint8List> takePicture() async {
      events.add('camera');
      return jpegBytes();
    }

    final first = await capture.capture(takePicture);
    final second = await capture.capture(takePicture);

    expect(events, ['location', 'camera', 'location', 'camera']);
    expect(first.location.latitude, 47.181912);
    expect(second.location.latitude, 47.181999);
    expect(first.location.measuredAtUtc, now);
    expect(
      second.location.measuredAtUtc,
      now.add(const Duration(seconds: 1)),
    );
    expect(first.capturedAtUtc.isUtc, isTrue);
    expect(second.capturedAtUtc, now.add(const Duration(seconds: 2)));
    expect(first.location.overlayText, '47.181912, 23.165123');
  });

  test('denied location access prevents taking a photo', () async {
    var cameraCalls = 0;

    final capture = PhotoCaptureService(
      readLocation: () async => throw const CaptureException('location_denied'),
    );

    await expectLater(
      capture.capture(() async {
        cameraCalls++;
        return jpegBytes();
      }),
      throwsA(
        isA<CaptureException>().having(
              (error) => error.code,
          'code',
          'location_denied',
        ),
      ),
    );

    expect(cameraCalls, 0);
  });

  test('an old location is rejected before taking a photo', () async {
    var cameraCalls = 0;

    final capture = PhotoCaptureService(
      readLocation: () async =>
          location(measuredAt: now.subtract(const Duration(minutes: 1))),
      clock: () => now,
    );

    await expectLater(
      capture.capture(() async {
        cameraCalls++;
        return jpegBytes();
      }),
      throwsA(
        isA<CaptureException>().having(
              (error) => error.code,
          'code',
          'location_unavailable',
        ),
      ),
    );

    expect(cameraCalls, 0);
  });

  test('a PNG capture keeps its format and original bytes', () async {
    final bytes = Uint8List.fromList([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01,
    ]);
    final capture = PhotoCaptureService(
      readLocation: () async => location(),
      clock: () => now,
      newId: () => 'web-photo',
    );

    final photo = await capture.capture(() async => bytes);

    expect(photo.mimeType, 'image/png');
    expect(photo.filename, 'web-photo.png');
    expect(photo.originalBytes, orderedEquals(bytes));
  });

  test('an unsupported image is not added as a photo', () async {
    final capture = PhotoCaptureService(
      readLocation: () async => location(),
      clock: () => now,
    );

    await expectLater(
      capture.capture(() async => Uint8List.fromList([1, 2, 3])),
      throwsA(
        isA<CaptureException>().having(
              (error) => error.code,
          'code',
          'invalid_photo',
        ),
      ),
    );
  });

  test('a draft preserves an immutable copy of the original bytes', () async {
    final original = jpegBytes();
    final capture = PhotoCaptureService(
      readLocation: () async => location(),
      clock: () => now,
      newId: () => 'photo-1',
    );

    final photo = await capture.capture(() async => original);
    original[0] = 0;

    expect(photo.originalBytes.first, 0xff);
    expect(photo.mimeType, 'image/jpeg');
    expect(photo.filename, 'photo-1.jpg');
    expect(
          () => photo.originalBytes[0] = 0,
      throwsUnsupportedError,
    );
  });

  test('removing one photo preserves the other photo and its location',
          () async {
        final store = PhotoDraftStore();
        addTearDown(store.dispose);

        await store.capture(() async => draft('first'));
        await store.capture(() async => draft('second', latitude: 48.123456));

        store.remove('first');

        expect(store.items.length, 1);
        expect(store.items.single.id, 'second');
        expect(store.items.single.location.latitude, 48.123456);
      });

  test('a pending capture prevents a duplicate request', () async {
    final pending = Completer<PhotoDraft>();
    final store = PhotoDraftStore();
    addTearDown(store.dispose);
    var calls = 0;

    Future<PhotoDraft> action() {
      calls++;
      return pending.future;
    }

    final first = store.capture(action);
    await store.capture(action);

    expect(calls, 1);
    expect(store.isCapturing, isTrue);

    pending.complete(draft('first'));
    await first;

    expect(store.items.length, 1);
    expect(store.isCapturing, isFalse);
  });

  test('a failed capture preserves existing photos', () async {
    final store = PhotoDraftStore();
    addTearDown(store.dispose);

    await store.capture(() async => draft('first'));
    await store.capture(
          () async => throw const CaptureException('location_timeout'),
    );

    expect(store.items.single.id, 'first');
    expect(store.errorCode, 'location_timeout');
    expect(store.isCapturing, isFalse);
  });

  test('a completed request cannot update a disposed store', () async {
    final pending = Completer<PhotoDraft>();
    final store = PhotoDraftStore();
    var notifications = 0;
    store.addListener(() => notifications++);

    final work = store.capture(() => pending.future);
    store.dispose();
    final notificationsBeforeCompletion = notifications;

    pending.complete(draft('first'));
    await work;

    expect(store.items, isEmpty);
    expect(notifications, notificationsBeforeCompletion);
  });
}