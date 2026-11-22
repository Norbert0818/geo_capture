import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/models/photo_location.dart';
import 'package:geo_capture/features/capture/photo_draft.dart';
import 'package:geo_capture/features/capture/photo_stamp_service.dart';
import 'package:geo_capture/features/capture/photo_stamp_style.dart';
import 'package:image/image.dart' as img;

PhotoDraft photo(int width, int height, {bool negative = false}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(180, 190, 200));
  final time = DateTime.utc(2026, 11, 22, 12);
  return PhotoDraft(
    id: 'readability-test',
    originalBytes: Uint8List.fromList(img.encodePng(image)),
    mimeType: 'image/png',
    capturedAt: time,
    location: PhotoLocation(
      latitude: negative ? -90 : 47.181912,
      longitude: negative ? -180 : 23.165123,
      accuracyMeters: 5,
      measuredAt: time,
    ),
  );
}

int whiteTextHeight(img.Image image) {
  var top = image.height;
  var bottom = -1;
  for (final pixel in image) {
    if (pixel.r > 235 && pixel.g > 235 && pixel.b > 235) {
      if (pixel.y < top) top = pixel.y;
      if (pixel.y > bottom) bottom = pixel.y;
    }
  }
  return bottom < top ? 0 : bottom - top + 1;
}

void main() {
  test('readability defaults use a larger but bounded text height', () {
    const style = PhotoStampStyle();
    expect(style.textHeight(480), 20);
    expect(style.textHeight(1080), closeTo(37.8, .001));
    expect(style.textHeight(4000), 84);
  });

  for (final size in [(800, 600), (600, 800)]) {
    test('actual JPEG text grows on ${size.$1} by ${size.$2} photos', () async {
      final draft = photo(size.$1, size.$2);
      final before = await PhotoStampService(
        style: const PhotoStampStyle(
          relativeTextHeight: .027,
          minTextHeight: 16,
          maxTextHeight: 64,
        ),
      ).stamp(draft);
      final after = await PhotoStampService().stamp(draft);
      final oldHeight = whiteTextHeight(img.decodeJpg(before.bytes)!);
      final newHeight = whiteTextHeight(img.decodeJpg(after.bytes)!);
      expect(oldHeight, greaterThan(0));
      expect(newHeight, greaterThanOrEqualTo(oldHeight + 2));
      expect(after.overlayText, '47.181912, 23.165123');
      expect(after.width, size.$1);
      expect(after.height, size.$2);
    });
  }

  for (final size in [(320, 240), (240, 320)]) {
    test(
      'long negative coordinates fit ${size.$1} by ${size.$2} photos',
          () async {
        final result = await PhotoStampService().stamp(
          photo(size.$1, size.$2, negative: true),
        );
        final decoded = img.decodeJpg(result.bytes)!;
        expect(result.overlayText, '-90.000000, -180.000000');
        expect(decoded.width, size.$1);
        expect(decoded.height, size.$2);
        expect(whiteTextHeight(decoded), greaterThan(0));
        final top = decoded.getPixel(decoded.width ~/ 2, 10);
        expect(top.r, closeTo(180, 6));
      },
    );
  }

  test(
    'very small source images remain valid and keep their dimensions',
        () async {
      final result = await PhotoStampService().stamp(
        photo(24, 12, negative: true),
      );
      final decoded = img.decodeJpg(result.bytes)!;
      expect(decoded.width, 24);
      expect(decoded.height, 12);
    },
  );
}