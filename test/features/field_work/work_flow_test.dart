import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/field_work/work_flow.dart';
import 'package:geo_capture/features/field_work/work_models.dart';

import 'work_test_support.dart';

final reviewPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAIAAADkharWAAAAF0lEQVR4nGN0y5vGQApgIkn1qIYRpAEAER0BYmrANbUAAAAASUVORK5CYII=',
  ),
);

WorkDocument reviewDocument(WorkKind kind, {bool local = true}) {
  final source = sampleWorkDocument(kind: kind, local: false);
  return source.copyWith(
    photos: [
      for (final photo in source.photos)
        local ? photo.withBytes(reviewPng, reviewPng) : photo,
    ],
  );
}

WorkPhoto changedReviewPhoto(
    WorkPhoto photo, {
      String? locality,
      String? county,
      bool? serialVisible,
      String? id,
    }) => WorkPhoto(
  id: id ?? photo.id,
  role: photo.role,
  location: photo.location,
  capturedAt: photo.capturedAtUtc,
  utcOffsetMinutes: photo.utcOffsetMinutes,
  locality: locality ?? photo.locality,
  county: county ?? photo.county,
  placeSource: photo.placeSource,
  serialVisible: serialVisible ?? photo.serialVisible,
  originalMimeType: photo.originalMimeType,
  original: photo.original,
  stamped: photo.stamped,
);

void main() {
  final expected = {
    WorkKind.replacement: ['oldIdentity', 'old', 'newIdentity', 'new'],
    WorkKind.repair: ['before', 'identity', 'after'],
    WorkKind.removal: ['identity', 'pole'],
    WorkKind.pit: ['pit'],
  };
  for (final entry in expected.entries) {
    test(
      '${entry.key.name} has the required sequence and a complete reviewable draft',
          () {
        expect(workFlow(entry.key).map((step) => step.key), entry.value);
        final draft = WorkDraft(
          id: workId,
          document: reviewDocument(entry.key),
        );
        expect(firstInvalidWorkStep(draft), isNull);
        for (var index = 0; index < entry.value.length; index++) {
          expect(workStepComplete(draft.document, index), isTrue);
        }
      },
    );
    for (final role in workRoles[entry.key]!) {
      test('${entry.key.name} points to a missing $role photo', () {
        final document = reviewDocument(entry.key);
        final invalid = document.copyWith(
          photos: document.photos.where((p) => p.role != role).toList(),
        );
        expect(
          firstInvalidWorkStep(WorkDraft(id: workId, document: invalid)),
          workFlow(entry.key).indexWhere((step) => step.key == role),
        );
      });
    }
  }

  test('old identity is required while old NTET remains optional', () {
    final document = reviewDocument(WorkKind.replacement);
    expect(workStepComplete(document, 0), isTrue);
    expect(
      firstInvalidWorkStep(
        WorkDraft(
          id: workId,
          document: document.copyWith(oldPole: const PoleIdentity()),
        ),
      ),
      0,
    );
  });

  test('a new pole requires NTET beyond its serial number', () {
    final document = reviewDocument(WorkKind.replacement).copyWith(
      newPole: const PoleIdentity(serialNumber: '0007', ntetCode: '   '),
    );
    expect(firstInvalidWorkStep(WorkDraft(id: workId, document: document)), 2);
  });

  test('every old-pole photo needs serial visibility confirmation', () {
    final document = reviewDocument(WorkKind.replacement);
    final bad = changedReviewPhoto(
      document.photos.first,
      serialVisible: false,
      id: versionId,
    );
    final withExtra = document.copyWith(photos: [...document.photos, bad]);
    expect(firstInvalidWorkStep(WorkDraft(id: workId, document: withExtra)), 1);
  });

  test('blank locality or county points back to the photo phase', () {
    final document = reviewDocument(WorkKind.repair);
    for (final photo in [
      changedReviewPhoto(document.photos.first, locality: ' '),
      changedReviewPhoto(document.photos.first, county: ''),
    ]) {
      expect(
        firstInvalidWorkStep(
          WorkDraft(
            id: workId,
            document: document.copyWith(
              photos: [photo, ...document.photos.skip(1)],
            ),
          ),
        ),
        0,
      );
    }
  });

  test(
    'revision reasons require three characters while a new work needs no entered reason',
        () {
      final document = reviewDocument(WorkKind.pit);
      expect(
        firstInvalidWorkStep(
          WorkDraft(id: workId, document: document, reason: ''),
        ),
        isNull,
      );
      expect(
        firstInvalidWorkStep(
          WorkDraft(
            id: workId,
            document: document,
            expectedVersion: versionId,
            reason: 'ab',
          ),
        ),
        0,
      );
      expect(
        firstInvalidWorkStep(
          WorkDraft(
            id: workId,
            document: document,
            expectedVersion: versionId,
            reason: 'abc',
          ),
        ),
        isNull,
      );
    },
  );

  test('the document photo limit still prevents a confirmed upload', () {
    final document = reviewDocument(WorkKind.pit);
    final photos = List.generate(
      11,
          (index) => changedReviewPhoto(document.photos.single, id: 'photo-$index'),
    );
    expect(
      firstInvalidWorkStep(
        WorkDraft(
          id: workId,
          document: document.copyWith(photos: photos),
        ),
      ),
      0,
    );
  });
}