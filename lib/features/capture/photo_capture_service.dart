import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/photo_location.dart';
import 'photo_draft.dart';

class PhotoCaptureService {
  PhotoCaptureService({
    Future<PhotoLocation> Function()? readLocation,
    DateTime Function()? clock,
    String Function()? newId,
  }) : _readLocation = readLocation ?? _deviceLocation,
       _clock = clock ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final Future<PhotoLocation> Function() _readLocation;
  final DateTime Function() _clock;
  final String Function() _newId;

  Future<PhotoDraft> capture(Future<Uint8List> Function() takePicture) async {
    final location = await _readLocation();
    final capturedAt = _clock().toUtc();

    if (capturedAt.difference(location.measuredAtUtc).abs() >
        const Duration(seconds: 30)) {
      throw const CaptureException('location_unavailable');
    }

    final bytes = await takePicture();
    final mimeType = _detectMimeType(bytes);

    return PhotoDraft(
      id: _newId(),
      originalBytes: bytes,
      mimeType: mimeType,
      capturedAt: capturedAt,
      location: location,
    );
  }

  static Future<void> prepareLocation() async {
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        throw const CaptureException('location_disabled');
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(
          const Duration(seconds: 45),
        );
      }

      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const CaptureException('location_denied');
      }
    } on CaptureException {
      rethrow;
    } on TimeoutException {
      throw const CaptureException('location_timeout');
    } catch (_) {
      throw const CaptureException('location_unavailable');
    }
  }

  static Future<PhotoLocation> _deviceLocation() async {
    await prepareLocation();

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );

      return PhotoLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        measuredAt: position.timestamp,
      );
    } on TimeoutException {
      throw const CaptureException('location_timeout');
    } on PermissionDeniedException {
      throw const CaptureException('location_denied');
    } on LocationServiceDisabledException {
      throw const CaptureException('location_disabled');
    } catch (_) {
      throw const CaptureException('location_unavailable');
    }
  }

  static String _detectMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }

    const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

    if (bytes.length >= png.length) {
      var matches = true;

      for (var index = 0; index < png.length; index++) {
        if (bytes[index] != png[index]) matches = false;
      }

      if (matches) return 'image/png';
    }

    throw const CaptureException('invalid_photo');
  }
}
