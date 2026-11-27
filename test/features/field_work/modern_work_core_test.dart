import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/field_work/romania_places.dart';
import 'package:geo_capture/features/field_work/work_controller.dart';
import 'package:geo_capture/features/field_work/work_flow.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_photo_names.dart';

import 'modern_work_test_support.dart';
import 'work_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'full bundled catalogue has 42 counties and 13755 locality entries',
        () async {
      final places = await RomaniaPlaces.load();
      expect(places.counties, hasLength(42));
      expect(places.localityCount, 13755);
      expect(places.county('51')!.name, 'Călărași');
      expect(places.county('52')!.name, 'Giurgiu');
      expect(places.place('59443')!.name, 'Sâncraiu');
      expect(
        places
            .search('sancraiu', countyCode: '12')
            .any((x) => x.code == '59443'),
        isTrue,
      );
    },
  );
  test('catalogue matching tolerates Romanian accents but ambiguous names require a choice', () {
    final places = smallCatalogue();
    expect(places.match('Sâncraiu', 'Județul Cluj')!.code, '59443');
    expect(places.match('Sancraiu', 'Cluj')!.code, '59443');
    expect(places.match('Valea', 'Cluj'), isNull);
    expect(places.search('val', countyCode: '12').map((x) => x.unit), [
      'Alpha',
      'Beta',
    ]);
    expect(places.search('zalau', countyCode: '12'), isEmpty);
    expect(places.search('zalau').single.countyCode, '31');
  });
  for (final state in ['missing', 'damaged']) {
    test('$state explicitly allows a repair without a serial', () {
      final document = modernDocument(kind: WorkKind.repair).copyWith(
        oldPole: confirmedPole(serial: '', state: state),
      );
      expect(document.complete, isTrue);
      expect(document.readyToSave, isTrue);
    });
  }
  test('numeric serials preserve zeros and reject letters, spaces and Unicode digits', () {
    expect(confirmedPole(serial: '00012').valid, isTrue);
    for (final serial in ['A123', '12 34', '+123', '１２３', '١٢٣', '123\n', '']) {
      expect(confirmedPole(serial: serial).valid, isFalse);
    }
  });
  test('a label photo cannot replace a required overview', () {
    final document = modernDocument().copyWith(
      photos: [modernPhoto(role: 'old_label')],
    );
    expect(document.complete, isFalse);
    expect(document.copyWith(progress: 'in_progress').readyToSave, isTrue);
  });
  test('old and new pole photos can be saved separately in progress', () {
    final document = WorkDocument(
      kind: WorkKind.replacement,
      schemaVersion: 2,
      progress: 'in_progress',
      photos: [modernPhoto(role: 'old')],
    );
    expect(document.complete, isFalse);
    expect(document.readyToSave, isTrue);
    expect(workFlowFor(document).map((x) => x.key), ['old', 'new']);
    expect(document.copyWith(progress: 'completed').readyToSave, isFalse);
  });
  test('modern identity evidence must belong to the correct pole', () {
    final document = modernDocument();
    expect(
      document
          .copyWith(newPole: confirmedPole().copyWith(evidencePhotoId: photoId))
          .readyToSave,
      isFalse,
    );
  });
  test('old JSON round trips without introducing new null properties', () {
    final doc = sampleWorkDocument(kind: WorkKind.replacement, local: false);
    final oldJson = jsonEncode(doc.toJson());
    for (final key in [
      'schemaVersion',
      'progress',
      'serialState',
      'confirmed',
      'evidencePhotoId',
      'countyCode',
      'localityCode',
    ]) {
      expect(oldJson, isNot(contains('"$key"')));
    }
    expect(jsonEncode(WorkDocument.fromJson(doc.toJson()).toJson()), oldJson);
  });
  test('partial upload preserves frozen retry payload and removes local draft only after acknowledgement', () async {
    final store = MemoryWorkStore(), repo = FakeWorkRepository();
    final document = WorkDocument(
      kind: WorkKind.replacement,
      schemaVersion: 2,
      progress: 'in_progress',
      photos: [modernPhoto(role: 'old')],
    );
    final controller = WorkController(
      draft: WorkDraft(id: workId, document: document),
      store: store,
      repository: repo,
      newId: () => versionId,
    );
    addTearDown(controller.dispose);
    await controller.persist();
    repo.onSave = (_) async => throw StateError('connection lost');
    expect(await controller.upload(), isNull);
    expect(controller.locked, isTrue);
    final frozen = jsonEncode(controller.draft.document.toJson());
    await controller.update(
      document.copyWith(notes: 'Must not change a pending request'),
    );
    expect(jsonEncode(controller.draft.document.toJson()), frozen);
    repo.onSave = null;
    expect(await controller.upload(), isNotNull);
    expect(store.drafts, isEmpty);
    expect(repo.sent.map((x) => x.pendingChangeId), [versionId, versionId]);
  });
  test(
    'serial-based photo names are stable, unique and match API convention',
        () {
      final document = modernDocument(kind: WorkKind.repair);
      expect(
        workPhotoName(workId, document, 0),
        '0002610586_inainte_01_11111111_22222222222242228222222222222222.stamped.jpg',
      );
      expect(
        workPhotoName(workId, document, 0, original: true),
        endsWith('.original.png'),
      );
      expect(
        workPhotoName(workId, document, 1),
        isNot(workPhotoName(workId, document, 0)),
      );
      final missing = document.copyWith(
        oldPole: confirmedPole(serial: '', state: 'missing'),
      );
      expect(workPhotoName(workId, missing, 0), startsWith('fara_serie_'));
    },
  );
}