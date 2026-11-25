import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:image/image.dart' as img;

import '../capture/photo_stamp_style.dart';
import 'work_models.dart';

class WorkPlace {
  const WorkPlace(this.locality, this.county);

  final String locality, county;
}

class WorkPlaceService {
  Future<WorkPlace?> lookup(WorkPhoto photo) async {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return null;
    }

    try {
      final geocoding = geo.Geocoding();

      final values = await geocoding
          .placemarkFromCoordinates(
        photo.location.latitude,
        photo.location.longitude,
        locale: const ui.Locale('ro', 'RO'),
      )
          .timeout(const Duration(seconds: 8));

      for (final value in values) {
        final locality =
            (value.locality?.trim().isNotEmpty == true
                ? value.locality
                : value.subLocality)
                ?.trim() ??
                '';

        final county = value.administrativeArea?.trim() ?? '';

        if (locality.isNotEmpty && county.isNotEmpty) {
          return WorkPlace(locality, county);
        }
      }
    } catch (_) {
      // Manual locality and county remain available.
    }

    return null;
  }
}

class WorkStampService {
  Future<WorkPhoto> stamp(WorkPhoto photo, Uint8List original) async {
    final paragraph =
    (ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 48, fontFamily: 'Roboto'),
    )
      ..pushStyle(
        ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontSize: 48,
          fontFamily: 'Roboto',
        ),
      )
      ..addText(photo.overlayText))
        .build()
      ..layout(const ui.ParagraphConstraints(width: 1800));

    final width = math.min(1832, paragraph.longestLine.ceil() + 32);
    final height = paragraph.height.ceil() + 32;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xFF141820), ui.BlendMode.src);

    canvas.drawParagraph(paragraph, const ui.Offset(16, 16));

    final picture = recorder.endRecording();
    final label = await picture.toImage(width, height);
    final labelData = await label.toByteData(format: ui.ImageByteFormat.png);

    label.dispose();
    picture.dispose();
    paragraph.dispose();

    if (labelData == null) {
      throw StateError('work_stamp_failed');
    }

    final result = await compute(_compositeWorkStamp, [
      original,
      labelData.buffer.asUint8List(),
    ]);

    return photo.withBytes(original, result);
  }
}

Uint8List _compositeWorkStamp(List<Uint8List> request) {
  var photo = img.decodeImage(request[0]);
  final label = img.decodePng(request[1]);

  if (photo == null || label == null) {
    throw const FormatException('Invalid work photo');
  }

  photo = img.bakeOrientation(photo);

  if (photo.hasPalette) {
    photo = photo.convert(numChannels: 3);
  }

  final short = math.min(photo.width, photo.height);
  final margin = math.max(1, (short * .015).round());

  final scale = math.min(
    const PhotoStampStyle().textHeight(short) / 48,
    math.min(
      (photo.width - margin * 2) / label.width,
      photo.height * .28 / label.height,
    ),
  );

  final resized = img.copyResize(
    label,
    width: math.max(1, (label.width * scale).round()),
    height: math.max(1, (label.height * scale).round()),
    interpolation: img.Interpolation.cubic,
  );

  photo = img.compositeImage(
    photo,
    resized,
    dstX: margin,
    dstY: math.max(0, photo.height - margin - resized.height),
  );

  photo.exif = img.ExifData();

  return Uint8List.fromList(img.encodeJpg(photo, quality: 92));
}