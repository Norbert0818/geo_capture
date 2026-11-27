import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import 'serial_reading.dart';

SerialPhotoReader createReader() => NativeSerialPhotoReader();

class NativeSerialPhotoReader implements SerialPhotoReader {
  NativeSerialPhotoReader({
    bool? supported,
    Future<Directory> Function()? temporaryDirectory,
  }) : _supported = supported ?? (Platform.isAndroid || Platform.isIOS),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;
  final bool _supported;
  final Future<Directory> Function() _temporaryDirectory;

  @override
  Future<SerialReading> read(Uint8List original) async {
    if (!_supported) return const SerialReading(supported: false);
    try {
      // A timeout releases the UI; the native operation's own finally block
      // still owns recognizer closure and private-file cleanup when it finishes.
      return await _read(original).timeout(const Duration(seconds: 20));
    } catch (_) {
      return const SerialReading(failed: true);
    }
  }

  Future<SerialReading> _read(Uint8List original) async {
    final root = await _temporaryDirectory();
    final directory = await root.createTemp('geocapture-label-');
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final scanner = MobileScannerController(autoStart: false);
    try {
      final bytes = await compute(_prepare, original);
      final file = File('${directory.path}/original.jpg');
      await file.writeAsBytes(bytes, flush: true);
      final codes = <String>[];
      try {
        final capture = await scanner.analyzeImage(file.path);
        for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
          if (barcode.rawValue != null) codes.add(barcode.rawValue!);
        }
      } catch (_) {
        /* OCR also works when barcode analysis is unavailable. */
      }
      final passages = <String>[];
      try {
        final result = await recognizer.processImage(
          InputImage.fromFilePath(file.path),
        );
        passages.add(result.text);
        final lines = result.blocks.expand((block) => block.lines).toList();
        final markers = lines
            .where((line) => SerialCandidates.containsLabel(line.text))
            .toList();
        // Re-read a label-sized area at full resolution, with less surrounding
        // pole/telephone/date text. At most one additional OCR pass is needed.
        if (markers.isNotEmpty) {
          final rect = markers.first.boundingBox;
          if (rect.left.isFinite &&
              rect.top.isFinite &&
              rect.width.isFinite &&
              rect.height.isFinite &&
              rect.width > 0 &&
              rect.height > 0) {
            final crop = await compute(_crop, (
            bytes,
            rect.left,
            rect.top,
            rect.width,
            rect.height,
            ));
            if (crop != null) {
              final cropped = File('${directory.path}/label.jpg');
              await cropped.writeAsBytes(crop, flush: true);
              passages.add(
                (await recognizer.processImage(
                  InputImage.fromFilePath(cropped.path),
                )).text,
              );
            }
          }
        }
      } catch (_) {
        if (codes.isEmpty && passages.isEmpty) {
          return const SerialReading(failed: true);
        }
      }
      return SerialReading(
        candidates: SerialCandidates.extract(qr: codes, text: passages),
      );
    } finally {
      try {
        await recognizer.close();
      } catch (_) {
        /* Native session already closed. */
      }
      try {
        await scanner.dispose();
      } catch (_) {
        /* No live camera session was started. */
      }
      try {
        await directory.delete(recursive: true);
      } catch (_) {
        /* OS cache cleanup remains available. */
      }
    }
  }
}

Uint8List _prepare(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Invalid label image');
  image = img.bakeOrientation(image);
  final maximum = math.max(image.width, image.height);
  if (maximum > 4096) {
    image = img.copyResize(
      image,
      width: (image.width * 4096 / maximum).round(),
      height: (image.height * 4096 / maximum).round(),
    );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

Uint8List? _crop((Uint8List, double, double, double, double) request) {
  final image = img.decodeImage(request.$1);
  if (image == null) return null;
  final left = math.max(0, (request.$2 - request.$5).floor());
  final top = math.max(0, (request.$3 - request.$5).floor());
  final right = image.width;
  final bottom = math.min(image.height, (request.$3 + request.$5 * 4).ceil());
  if (right <= left || bottom <= top) return null;
  var crop = img.copyCrop(
    image,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
  if (crop.width < 1600) {
    crop = img.copyResize(
      crop,
      width: 1600,
      interpolation: img.Interpolation.cubic,
    );
  }
  return Uint8List.fromList(img.encodeJpg(crop, quality: 95));
}