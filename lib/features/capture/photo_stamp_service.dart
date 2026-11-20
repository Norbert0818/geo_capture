import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'photo_draft.dart';
import 'stamped_photo.dart';

class PhotoStampService {
  Future<StampedPhoto> stamp(PhotoDraft photo) async {
    try {
      return await compute(
        _stampPhoto,
        _StampRequest(photo.originalBytes, photo.location.overlayText),
        debugLabel: 'photo-stamp',
      );
    } catch (_) {
      throw const CaptureException('photo_processing_failed');
    }
  }
}

class _StampRequest {
  const _StampRequest(this.bytes, this.overlayText);

  final Uint8List bytes;
  final String overlayText;
}

StampedPhoto _stampPhoto(_StampRequest request) {
  var photo = img.decodeImage(request.bytes);

  if (photo == null) {
    throw const CaptureException('photo_processing_failed');
  }

  if (photo.exif.imageIfd.hasOrientation &&
      photo.exif.imageIfd.orientation != 1) {
    photo = img.bakeOrientation(photo);
  }

  // Palette images need RGB pixels before compositing new colors.
  if (photo.hasPalette) {
    photo = photo.convert(numChannels: 3);
  }

  final font = img.arial48;
  var textWidth = 0;

  for (final code in request.overlayText.codeUnits) {
    textWidth += font.characters[code]!.xAdvance;
  }

  const padding = 16;
  final label = img.Image(
    width: textWidth + padding * 2,
    height: font.lineHeight + padding * 2,
    numChannels: 3,
  );

  img.fill(label, color: img.ColorRgb8(20, 24, 32));
  img.drawString(
    label,
    request.overlayText,
    font: font,
    x: padding,
    y: padding,
    color: img.ColorRgb8(255, 255, 255),
  );

  final shortEdge = math.min(photo.width, photo.height);
  final margin = math.min((shortEdge * 0.015).round(), (shortEdge - 1) ~/ 2);
  final lineHeight = (shortEdge * 0.027).clamp(16.0, 64.0);
  final availableWidth = photo.width - margin * 2;
  final availableHeight = photo.height - margin * 2;
  final scale = math.min(
    lineHeight / font.lineHeight,
    math.min(availableWidth / label.width, availableHeight / label.height),
  );

  final resizedLabel = img.copyResize(
    label,
    width: math.max(1, (label.width * scale).round()),
    height: math.max(1, (label.height * scale).round()),
    interpolation: img.Interpolation.cubic,
  );

  photo = img.compositeImage(
    photo,
    resizedLabel,
    dstX: margin,
    dstY: photo.height - margin - resizedLabel.height,
  );

  // Pixels already have the correct orientation. The original retains EXIF.
  photo.exif = img.ExifData();

  return StampedPhoto(
    bytes: img.encodeJpg(photo, quality: 92),
    width: photo.width,
    height: photo.height,
    overlayText: request.overlayText,
  );
}
