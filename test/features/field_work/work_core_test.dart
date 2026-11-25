import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/field_work/pole_code.dart';
import 'package:geo_capture/features/field_work/work_controller.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_storage.dart';
import 'package:sembast/sembast_memory.dart';

import 'work_test_support.dart';

void main() {
  test(
    'reads the exact manufacturer QR from the supplied photo without inventing NTET',
        () {
      final pole = PoleCode.read('Composite tip 7m R0_N°serie:2610586');
      expect(pole.serialNumber, '2610586');
      expect(pole.ntetCode, isEmpty);
      expect(pole.rawCode, 'Composite tip 7m R0_N°serie:2610586');
    },
  );
  test('generated QR round-trips both fields and preserves leading zeroes', () {
    const pole = PoleIdentity(
      serialNumber: '0002610586',
      ntetCode: 'T0PL0138RO',
    );
    final parsed = PoleCode.read(pole.generatedPayload);
    expect(parsed.serialNumber, pole.serialNumber);
    expect(parsed.ntetCode, pole.ntetCode);
    expect(jsonDecode(pole.generatedPayload)['version'], 1);
  });
  test('unknown QR text remains raw and never guesses an identity', () {
    final pole = PoleCode.read('https://example.com/unknown');
    expect(pole.serialNumber, isEmpty);
    expect(pole.ntetCode, isEmpty);
    expect(pole.rawCode, isNotEmpty);
  });
  test('supports labelled NTET and serial fields and numeric-only serials', () {
    final pole = PoleCode.read('NTET Cod: T0PL0138RO; N°Serie: 0002610586');
    expect(pole.ntetCode, 'T0PL0138RO');
    expect(pole.serialNumber, '0002610586');
    expect(PoleCode.read('0000001').serialNumber, '0000001');
  });
  test(
    'photo stamp contains six decimal coordinates, Unicode place and captured local time',
        () {
      final photo = sampleWorkPhoto();
      expect(
        photo.overlayText,
        '46.777987, 24.309925\nSâncraiu, Cluj\n2026-11-24 14:30:01 (UTC+02:00)',
      );
      expect(
        workTimestamp(DateTime.utc(2026, 1, 1, 1), -300),
        '2025-12-31 20:00:00 (UTC-05:00)',
      );
      expect(WorkPhoto.fromJson(photo.toJson()).overlayText, photo.overlayText);
    },
  );
  test('each operation requires its own photos and identity fields', () {
    for (final kind in WorkKind.values) {
      final doc = sampleWorkDocument(kind: kind);
      expect(doc.complete, isTrue, reason: kind.name);
      expect(doc.copyWith(photos: []).complete, isFalse);
    }
    final doc = sampleWorkDocument(kind: WorkKind.replacement);
    expect(
      doc.copyWith(newPole: const PoleIdentity(serialNumber: '0009')).complete,
      isFalse,
    );
  });
  test('photo bytes are frozen instead of sharing a mutable input buffer', () {
    final original = Uint8List.fromList([1, 2]);
    final photo = sampleWorkPhoto().withBytes(original, original);
    original[0] = 9;
    expect(photo.original![0], 1);
    expect(() => photo.original![0] = 7, throwsUnsupportedError);
  });

  group('durable drafts', () {
    test(
      'restores both image variants, fields and a frozen pending request',
          () async {
        final db = await databaseFactoryMemory.openDatabase('work-restore');
        addTearDown(db.close);
        final storage = SembastWorkStorage(
          server: 'https://api.example.com',
          openDatabase: () async => db,
        );
        final user = storage.forUser('owner');
        final draft = WorkDraft(
          id: workId,
          document: sampleWorkDocument(kind: WorkKind.replacement),
          pendingChangeId: versionId,
        );
        final revision = await user.write(draft);
        final restored = (await user.readAll()).single;
        expect(restored.localRevision, revision);
        expect(restored.pendingChangeId, versionId);
        expect(restored.document.newPole!.serialNumber, '0002610587');
        expect(restored.document.photos.first.original, [1, 2, 3]);
        expect(restored.document.photos.first.stamped, [4, 5, 6]);
      },
    );
    test('isolates drafts by API server and signed-in user', () async {
      final db = await databaseFactoryMemory.openDatabase('work-scopes');
      addTearDown(db.close);
      final one = SembastWorkStorage(
        server: 'https://one.example.com',
        openDatabase: () async => db,
      );
      final two = SembastWorkStorage(
        server: 'https://two.example.com',
        openDatabase: () async => db,
      );
      await one
          .forUser('alice')
          .write(WorkDraft(id: workId, document: sampleWorkDocument()));
      expect(await one.forUser('bob').readAll(), isEmpty);
      expect(await two.forUser('alice').readAll(), isEmpty);
    });
    test(
      'stale local revisions cannot overwrite another browser tab',
          () async {
        final db = await databaseFactoryMemory.openDatabase('work-cas');
        addTearDown(db.close);
        final user = SembastWorkStorage(
          server: 'https://api.example.com',
          openDatabase: () async => db,
        ).forUser('owner');
        final draft = WorkDraft(id: workId, document: sampleWorkDocument());
        await user.write(draft);
        await expectLater(user.write(draft), throwsStateError);
        expect((await user.readAll()).single.localRevision, 1);
      },
    );
  });

  group('upload acknowledgement', () {
    late MemoryWorkStore store;
    late FakeWorkRepository repository;
    late WorkController controller;
    setUp(() {
      store = MemoryWorkStore();
      repository = FakeWorkRepository();
      controller = WorkController(
        draft: WorkDraft(id: workId, document: sampleWorkDocument()),
        store: store,
        repository: repository,
        newId: () => versionId,
      );
    });
    tearDown(() => controller.dispose());

    test(
      'persists the change ID before sending and clears only after matching acknowledgement',
          () async {
        repository.onSave = (draft) async {
          expect(store.drafts[workId]!.pendingChangeId, versionId);
          return WorkDetails(
            id: draft.id,
            version: versionId,
            revision: 1,
            owner: 'worker',
            document: draft.document,
          );
        };
        expect(await controller.upload(), isNotNull);
        expect(store.drafts, isEmpty);
      },
    );
    test(
      'a network failure keeps photos and retries the exact same request',
          () async {
        repository.onSave = (_) async =>
        throw const ApiException('service_unavailable');
        expect(await controller.upload(), isNull);
        final first = repository.sent.single;
        await controller.update(
          controller.draft.document.copyWith(
            notes: 'must not change frozen payload',
          ),
        );
        expect(controller.draft.document.notes, isEmpty);
        repository.onSave = (draft) async => WorkDetails(
          id: draft.id,
          version: versionId,
          revision: 1,
          owner: 'worker',
          document: draft.document,
        );
        expect(await controller.upload(), isNotNull);
        expect(repository.sent.last.pendingChangeId, first.pendingChangeId);
        expect(
          jsonEncode(repository.sent.last.document.toJson()),
          jsonEncode(first.document.toJson()),
        );
      },
    );
    test('a mismatched acknowledgement cannot delete local evidence', () async {
      repository.onSave = (draft) async => WorkDetails(
        id: 'wrong-id',
        version: versionId,
        revision: 1,
        owner: 'worker',
        document: draft.document,
      );
      expect(await controller.upload(), isNull);
      expect(store.drafts[workId]!.document.photos.single.original, [1, 2, 3]);
      expect(controller.locked, isTrue);
    });
    test(
      'a definite validation rejection unlocks editing without losing the draft',
          () async {
        repository.onSave = (_) async => throw const ApiException(
          'work_qr_generation_disabled',
          statusCode: 400,
        );
        expect(await controller.upload(), isNull);
        expect(controller.draft.pendingChangeId, isNull);
        expect(controller.locked, isFalse);
        expect(store.drafts[workId]!.document.photos, isNotEmpty);
      },
    );
    test('a local write failure never sends an unpersisted upload', () async {
      store.failWrite = true;
      expect(await controller.upload(), isNull);
      expect(repository.sent, isEmpty);
      store.failWrite = false;
      await controller.persist();
      expect(await controller.upload(), isNotNull);
    });
    test(
      'local cleanup failure keeps the same pending request for safe replay',
          () async {
        store.failRemove = true;
        expect(await controller.upload(), isNull);
        final change = controller.draft.pendingChangeId;
        store.failRemove = false;
        expect(await controller.upload(), isNotNull);
        expect(repository.sent.last.pendingChangeId, change);
      },
    );
    test(
      'a CSRF rejection keeps the original request identity until its outcome is known',
          () async {
        repository.onSave = (_) async =>
        throw const ApiException('csrf_invalid', statusCode: 400);
        expect(await controller.upload(), isNull);
        expect(controller.draft.pendingChangeId, versionId);
        expect(controller.locked, isTrue);
      },
    );
  });
}