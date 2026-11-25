import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_qr_page.dart';
import 'package:geo_capture/features/field_work/work_stamp_service.dart';
import 'package:image/image.dart' as img;

import 'work_test_support.dart';

void main() {
  setUpAll(() async {
    // Use the SDK's Roboto when available, so the saved diagnostic stamp has real glyphs.
    final config = File('.dart_tool/package_config.json');
    if (!config.existsSync()) return;
    final packages =
    (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
    final flutter = packages.cast<Map>().firstWhere(
          (value) => value['name'] == 'flutter',
    );
    final package = Directory.fromUri(
      config.absolute.uri.resolve(flutter['rootUri'] as String),
    );
    final font = File(
      '${package.parent.parent.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    if (!font.existsSync()) return;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
    await loader.load();
  });
  testWidgets(
    'multiline Unicode stamp keeps the original bytes and bakes photo orientation',
        (tester) async {
      await tester.pumpWidget(const SizedBox(width: 10, height: 10));
      final source = img.Image(width: 800, height: 600);
      img.fill(source, color: img.ColorRgb8(160, 170, 180));
      source.exif.imageIfd.orientation = 6;
      final original = Uint8List.fromList(img.encodeJpg(source));
      final sample = sampleWorkPhoto();
      final photo = WorkPhoto(
        id: photoId,
        role: 'pit',
        location: sample.location,
        capturedAt: sample.capturedAtUtc,
        utcOffsetMinutes: 120,
        locality: 'Sâncraiu – Șăulia',
        county: 'Bistrița-Năsăud',
        placeSource: 'manual',
        serialVisible: false,
        originalMimeType: 'image/jpeg',
      );
      final result = await tester.runAsync(
            () => WorkStampService().stamp(photo, original),
      );
      expect(result!.original, original);
      expect(result.capturedAtUtc, photo.capturedAtUtc);
      expect(result.overlayText, contains('Sâncraiu – Șăulia'));
      final decoded = img.decodeJpg(result.stamped!)!;
      expect(decoded.width, 600);
      expect(decoded.height, 800);
      expect(decoded.exif.imageIfd.orientation, isNull);
      final output = File('build/fieldwork-check/stamp.jpg');
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(result.stamped!);
    },
  );

  testWidgets('QR export has an opaque quiet zone and a fixed square size', (
      tester,
      ) async {
    await tester.pumpWidget(const SizedBox(width: 10, height: 10));
    const pole = PoleIdentity(
      serialNumber: '0002610587',
      ntetCode: 'T0PL0138RO',
    );
    final bytes = await tester.runAsync(
          () => renderWorkQr(pole.generatedPayload),
    );
    final image = img.decodePng(bytes!)!;
    expect(image.width, 1024);
    expect(image.height, 1024);
    final corner = image.getPixel(8, 8);
    expect(corner.r, 255);
    expect(corner.g, 255);
    expect(corner.b, 255);
    final output = File('build/fieldwork-check/qr.png');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes);
  });
}
