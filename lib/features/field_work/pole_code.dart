import 'dart:convert';

import 'work_models.dart';

class PoleCode {
  static PoleIdentity read(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.length > 4096) {
      throw const FormatException('Invalid barcode');
    }
    String serial = '', ntet = '';
    try {
      final json = jsonDecode(value);
      if (json is Map &&
          json['type'] == 'geocapture.pole' &&
          json['version'] == 1) {
        serial = json['serialNumber'] as String;
        ntet = json['ntetCode'] as String;
      }
    } on FormatException {
      /* Manufacturer text is also supported. */
    } on TypeError {
      throw const FormatException('Invalid pole code');
    }
    if (serial.isEmpty) {
      serial =
          RegExp(
            r'(?:n[°ºo.]?\s*serie|nr[.\s_-]*serie|serial(?:\s*number)?|serie)\s*[:=]\s*([A-Za-z0-9._/-]+)',
            caseSensitive: false,
          ).firstMatch(value)?.group(1) ??
          '';
      ntet =
          RegExp(
            r'NTET(?:\s*(?:Cd|Cod|Code)\.?)?\s*[:=]\s*([A-Za-z0-9._/-]+)',
            caseSensitive: false,
          ).firstMatch(value)?.group(1) ??
          ntet;
      if (serial.isEmpty && RegExp(r'^\d+$').hasMatch(value)) serial = value;
    }
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasQuery) {
      serial =
          uri.queryParameters['serialNumber'] ??
          uri.queryParameters['serial'] ??
          serial;
      ntet =
          uri.queryParameters['ntetCode'] ??
          uri.queryParameters['ntet'] ??
          ntet;
    }
    if (serial.length > 1024 || ntet.length > 128) {
      throw const FormatException('Pole code is too long');
    }
    // Missing fields stay empty: a serial-only QR never invents an NTET code.
    return PoleIdentity(
      serialNumber: serial.trim(),
      ntetCode: ntet.trim(),
      source: 'scanned',
      rawCode: value,
    );
  }
}