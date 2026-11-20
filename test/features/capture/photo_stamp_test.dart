import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:geo_capture/core/models/photo_location.dart';
import 'package:geo_capture/features/capture/photo_capture_service.dart';
import 'package:geo_capture/features/capture/photo_draft.dart';
import 'package:geo_capture/features/capture/photo_draft_store.dart';
import 'package:geo_capture/features/capture/photo_preparation_service.dart';
import 'package:geo_capture/features/capture/photo_stamp_service.dart';
import 'package:geo_capture/features/capture/stamped_photo.dart';

final capturedAt = DateTime.utc(2026, 11, 19, 12);

PhotoLocation fix({double latitude = 47.181912, double longitude = 23.165123}) {
  return PhotoLocation(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: 5,
    measuredAt: capturedAt.subtract(const Duration(seconds: 1)),
  );
}

Uint8List picture({int width = 320, int height = 240, bool jpeg = false}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(180, 190, 200));
  return jpeg ? img.encodeJpg(image, quality: 95) : img.encodePng(image);
}

PhotoDraft draft({
  Uint8List? bytes,
  String id = 'photo-1',
  String mimeType = 'image/png',
  PhotoLocation? location,
}) {
  return PhotoDraft(
    id: id,
    originalBytes: bytes ?? picture(),
    mimeType: mimeType,
    capturedAt: capturedAt,
    location: location ?? fix(),
  );
}

Matcher processingFailure() => isA<CaptureException>().having(
  (error) => error.code,
  'code',
  'photo_processing_failed',
);

void main() {
  for (final jpeg in [false, true]) {
    test(
      '${jpeg ? 'JPEG' : 'PNG'} input produces a decodable stamped JPEG',
      () async {
        final photo = draft(
          bytes: picture(jpeg: jpeg),
          mimeType: jpeg ? 'image/jpeg' : 'image/png',
        );

        final stamped = await PhotoStampService().stamp(photo);
        final decoded = img.decodeJpg(stamped.bytes);

        expect(decoded, isNotNull);
        expect(stamped.bytes.take(3), [0xff, 0xd8, 0xff]);
        expect(stamped.mimeType, 'image/jpeg');
        expect(stamped.overlayText, '47.181912, 23.165123');
      },
    );
  }

  for (final size in [(384, 256), (256, 384)]) {
    test('preserves upright dimensions ${size.$1} x ${size.$2}', () async {
      final photo = draft(
        bytes: picture(width: size.$1, height: size.$2),
      );

      final stamped = await PhotoStampService().stamp(photo);
      final decoded = img.decodeJpg(stamped.bytes)!;

      expect(decoded.width, size.$1);
      expect(decoded.height, size.$2);
      expect(stamped.width, decoded.width);
      expect(stamped.height, decoded.height);
    });
  }

  test(
    'processing keeps the exact original bytes and both copies are immutable',
    () async {
      final input = picture();
      final originalSnapshot = Uint8List.fromList(input);
      final photo = draft(bytes: input);

      final stamped = await PhotoStampService().stamp(photo);
      final prepared = photo.withStamp(stamped);
      input[0] = 0;

      expect(photo.originalBytes, orderedEquals(originalSnapshot));
      expect(prepared.originalBytes, orderedEquals(originalSnapshot));
      expect(photo.stamped, isNull);
      expect(prepared.stamped, isNotNull);
      expect(prepared.filename, 'photo-1.png');
      expect(prepared.stampedFilename, 'photo-1.coords.jpg');
      expect(() => prepared.originalBytes[0] = 0, throwsUnsupportedError);
      expect(() => prepared.stamped!.bytes[0] = 0, throwsUnsupportedError);
    },
  );

  test(
    'the encoded JPEG contains white text on a small dark bottom panel',
    () async {
      final photo = draft(bytes: picture(width: 640, height: 480));
      final stamped = await PhotoStampService().stamp(photo);
      final decoded = img.decodeJpg(stamped.bytes)!;
      var dark = 0;
      var white = 0;
      var changed = 0;

      for (final pixel in decoded) {
        if (pixel.y < decoded.height * 3 ~/ 4) continue;

        if (pixel.r < 60 && pixel.g < 60 && pixel.b < 60) dark++;
        if (pixel.r > 235 && pixel.g > 235 && pixel.b > 235) white++;
        if ((pixel.r - 180).abs() > 15 ||
            (pixel.g - 190).abs() > 15 ||
            (pixel.b - 200).abs() > 15) {
          changed++;
        }
      }

      expect(dark, greaterThan(100));
      expect(white, greaterThan(5));
      expect(changed, lessThan(decoded.width * decoded.height * 0.08));

      final upperPixel = decoded.getPixel(20, 20);
      expect(upperPixel.r, closeTo(180, 5));
      expect(upperPixel.g, closeTo(190, 5));
      expect(upperPixel.b, closeTo(200, 5));
    },
  );

  test('EXIF rotation is applied once before adding the coordinates', () async {
    final image = img.Image(width: 400, height: 300, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(230, 20, 20));
    img.fillRect(
      image,
      x1: 200,
      y1: 0,
      x2: 399,
      y2: 299,
      color: img.ColorRgb8(20, 20, 230),
    );
    image.exif.imageIfd.orientation = 6;
    final original = img.encodeJpg(image, quality: 95);
    final photo = draft(bytes: original, mimeType: 'image/jpeg');

    final stamped = await PhotoStampService().stamp(photo);
    final decoded = img.decodeJpg(stamped.bytes)!;

    expect(decoded.width, 300);
    expect(decoded.height, 400);
    final upperPixel = decoded.getPixel(150, 50);
    final lowerPixel = decoded.getPixel(150, 320);
    expect(upperPixel.r, greaterThan(upperPixel.b + 100));
    expect(lowerPixel.b, greaterThan(lowerPixel.r + 100));
    expect(photo.originalBytes, orderedEquals(original));
  });

  test(
    'different coordinates change actual image bytes and retain six decimals',
    () async {
      final bytes = picture();
      final service = PhotoStampService();
      final first = await service.stamp(draft(bytes: bytes));
      final second = await service.stamp(
        draft(
          bytes: bytes,
          location: fix(latitude: -0.0000001, longitude: -180),
        ),
      );

      expect(second.overlayText, '0.000000, -180.000000');
      expect(first.bytes, isNot(orderedEquals(second.bytes)));
    },
  );

  test(
    'a corrupt image is rejected instead of becoming a ready photo',
    () async {
      final photo = draft(bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 1]));

      await expectLater(
        PhotoStampService().stamp(photo),
        throwsA(processingFailure()),
      );
    },
  );

  test('attaching a stamp preserves capture and location metadata', () async {
    final photo = draft();
    final stamped = await PhotoStampService().stamp(photo);
    final prepared = photo.withStamp(stamped);

    expect(prepared.id, photo.id);
    expect(prepared.mimeType, photo.mimeType);
    expect(prepared.capturedAtUtc, capturedAt);
    expect(prepared.location.measuredAtUtc, photo.location.measuredAtUtc);
    expect(prepared.location.latitude, photo.location.latitude);
    expect(prepared.location.longitude, photo.location.longitude);
    expect(prepared.location.accuracyMeters, photo.location.accuracyMeters);
  });

  test(
    'a stamp with another location cannot be attached to the photo',
    () async {
      final first = draft();
      final second = draft(location: fix(latitude: 48.123456));
      final wrongStamp = await PhotoStampService().stamp(second);

      expect(() => first.withStamp(wrongStamp), throwsArgumentError);
    },
  );

  test(
    'two prepared captures keep their own IDs, GPS fixes and stamped files',
    () async {
      var index = 0;
      final locations = [fix(), fix(latitude: 48.123456)];
      final preparation = PhotoPreparationService(
        captureService: PhotoCaptureService(
          readLocation: () async => locations[index++],
          clock: () => capturedAt,
          newId: () => 'photo-$index',
        ),
      );
      final bytes = picture();

      final first = await preparation.capture(() async => bytes);
      final second = await preparation.capture(() async => bytes);

      expect(first.id, 'photo-1');
      expect(second.id, 'photo-2');
      expect(first.stamped!.overlayText, '47.181912, 23.165123');
      expect(second.stamped!.overlayText, '48.123456, 23.165123');
      expect(first.originalBytes, orderedEquals(bytes));
      expect(second.originalBytes, orderedEquals(bytes));
      expect(first.stamped!.bytes, isNot(orderedEquals(second.stamped!.bytes)));
    },
  );

  test(
    'failed processing keeps earlier photos and does not add a partial photo',
    () async {
      final store = PhotoDraftStore();
      addTearDown(store.dispose);
      final preparation = PhotoPreparationService(
        captureService: PhotoCaptureService(
          readLocation: () async => fix(),
          clock: () => capturedAt,
          newId: () => 'new-photo',
        ),
      );
      final previous = draft(id: 'previous');
      await store.capture(() async => previous);

      await store.capture(
        () => preparation.capture(
          () async => Uint8List.fromList([0xff, 0xd8, 0xff, 1]),
        ),
      );

      expect(store.items.length, 1);
      expect(store.items.single.id, 'previous');
      expect(store.errorCode, 'photo_processing_failed');
      expect(store.isCapturing, isFalse);
    },
  );

  test('the capture lock stays active until stamping finishes', () async {
    final pending = Completer<StampedPhoto>();
    final started = Completer<PhotoDraft>();
    final store = PhotoDraftStore();
    addTearDown(store.dispose);
    var cameraCalls = 0;
    final bytes = picture();
    final preparation = PhotoPreparationService(
      captureService: PhotoCaptureService(
        readLocation: () async => fix(),
        clock: () => capturedAt,
        newId: () => 'photo-1',
      ),
      stampPhoto: (photo) {
        started.complete(photo);
        return pending.future;
      },
    );

    Future<PhotoDraft> action() => preparation.capture(() async {
      cameraCalls++;
      return bytes;
    });

    final work = store.capture(action);
    final raw = await started.future;

    expect(store.isCapturing, isTrue);
    expect(store.items, isEmpty);
    await store.capture(action);
    expect(cameraCalls, 1);

    pending.complete(await PhotoStampService().stamp(raw));
    await work;

    expect(store.isCapturing, isFalse);
    expect(store.items.length, 1);
    expect(store.items.single.stamped, isNotNull);
  });
}
