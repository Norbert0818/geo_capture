import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

typedef WorkFileShare =
Future<void> Function(
    BuildContext context,
    Uint8List bytes,
    String filename,
    String mimeType,
    );

Future<void> shareWorkFile(
    BuildContext context,
    Uint8List bytes,
    String filename,
    String mimeType,
    ) async {
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType)],
      fileNameOverrides: [filename],
      downloadFallbackEnabled: true,
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

String workCsvFilename(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final utc = time.toUtc();
  return 'geocapture-works-${utc.year}${two(utc.month)}${two(utc.day)}-'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}.csv';
}

String workZipFilename(String id, int revision) =>
    'work_${id.replaceAll('-', '')}_v$revision.zip';