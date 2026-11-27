import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geo_capture/core/models/photo_location.dart';
import 'package:geo_capture/features/capture/photo_draft.dart';
import 'package:geo_capture/features/field_work/romania_places.dart';
import 'package:geo_capture/features/field_work/serial_reading.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import 'work_flow_test.dart' show reviewPng;
import 'work_test_support.dart';

RomaniaPlaces smallCatalogue() => RomaniaPlaces.fromJson({
  'format': 'geocapture.romania-places',
  'version': 1,
  'counties': [
    {'code': '12', 'name': 'Cluj'},
    {'code': '31', 'name': 'Sălaj'},
  ],
  'localities': [
    {
      'code': '59443',
      'countyCode': '12',
      'name': 'Sâncraiu',
      'unit': 'Sâncraiu',
    },
    {'code': '10001', 'countyCode': '12', 'name': 'Valea', 'unit': 'Alpha'},
    {'code': '10002', 'countyCode': '12', 'name': 'Valea', 'unit': 'Beta'},
    {
      'code': '10003',
      'countyCode': '31',
      'name': 'Zalău',
      'unit': 'Municipiul Zalău',
    },
  ],
});

PoleIdentity confirmedPole({
  String serial = '0002610586',
  String state = 'present',
}) => PoleIdentity(serialNumber: serial, serialState: state, confirmed: true);

WorkPhoto modernPhoto({
  String role = 'pole',
  String id = photoId,
  bool local = true,
}) => WorkPhoto(
  id: id,
  role: role,
  location: PhotoLocation(
    latitude: 46.777987,
    longitude: 24.309925,
    accuracyMeters: 3,
    measuredAt: DateTime.utc(2026, 11, 27, 10),
  ),
  capturedAt: DateTime.utc(2026, 11, 27, 10, 0, 1),
  utcOffsetMinutes: 120,
  locality: 'Sâncraiu',
  county: 'Cluj',
  countyCode: '12',
  localityCode: '59443',
  placeSource: 'catalog',
  serialVisible: false,
  originalMimeType: 'image/png',
  original: local ? reviewPng : null,
  stamped: local ? reviewPng : null,
);

WorkDocument modernDocument({
  WorkKind kind = WorkKind.replacement,
  String progress = 'completed',
  bool local = true,
}) => WorkDocument(
  kind: kind,
  schemaVersion: 2,
  progress: progress,
  oldPole: kind == WorkKind.pit ? null : confirmedPole(),
  newPole: kind == WorkKind.replacement
      ? confirmedPole(serial: '0002610587')
      : null,
  photos: [
    for (var i = 0; i < workRoles[kind]!.length; i++)
      modernPhoto(
        role: workRoles[kind]![i],
        id: i == 0 ? photoId : '44444444-4444-4444-8444-444444444444',
        local: local,
      ),
  ],
);

PhotoDraft captureDraft(String id) => PhotoDraft(
  id: id,
  originalBytes: reviewPng,
  mimeType: 'image/png',
  capturedAt: DateTime.utc(2026, 11, 27, 10, 0, 1),
  location: modernPhoto().location,
);

Widget modernShell(Widget child, {String language = 'en'}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: child,
);

class FakeSerialReader implements SerialPhotoReader {
  FakeSerialReader([this.result = const SerialReading()]);
  SerialReading result;
  final originals = <Uint8List>[];
  @override
  Future<SerialReading> read(Uint8List original) async {
    originals.add(original);
    return result;
  }
}