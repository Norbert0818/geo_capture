import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/models/session_user.dart';
import 'package:geo_capture/features/field_work/work_home_page.dart';
import 'package:geo_capture/features/field_work/serial_reading.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_stamp_service.dart';
import 'package:geo_capture/features/field_work/work_task_page.dart';
import 'package:geo_capture/features/field_work/work_storage.dart';
import 'package:sembast/sembast_memory.dart';

import 'modern_work_test_support.dart';
import 'serial_confirmation_test.dart' show serialTap;
import 'work_flow_test.dart' show reviewPng;
import 'work_test_support.dart';

Future<void> openTask(
    WidgetTester tester,
    WorkDraft draft,
    MemoryWorkStore store,
    FakeWorkRepository repo, {
      FakeSerialReader? reader,
      bool generation = false,
      String? scannedCode,
      String language = 'en',
    }) async {
  var captures = 0;
  await tester.pumpWidget(
    modernShell(
      Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => WorkTaskPage(
                  draft: draft,
                  store: store,
                  repository: repo,
                  allowGeneration: generation,
                  services: WorkTaskServices(
                    scanCode: scannedCode == null
                        ? null
                        : (_) async => scannedCode,
                    places: () async => smallCatalogue(),
                    reader: reader ?? FakeSerialReader(),
                    lookup: (_) async => const WorkPlace('Sâncraiu', 'Cluj'),
                    capture: (_, _) async => captureDraft(
                      '55555555-5555-4555-8555-${(++captures).toString().padLeft(12, '0')}',
                    ),
                    stamp: (photo, original) async =>
                        photo.withBytes(original, reviewPng),
                  ),
                ),
              ),
            ),
            child: const Text('Open task'),
          ),
        ),
      ),
      language: language,
    ),
  );
  await tester.tap(find.text('Open task'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the work list starts a modern repair with photo-first phases', (
      tester,
      ) async {
    final db = await databaseFactoryMemory.openDatabase('modern-home');
    addTearDown(db.close);
    await tester.pumpWidget(
      modernShell(
        WorkHomePage(
          user: SessionUser(
            id: workId,
            username: 'worker',
            roles: ['User'],
            mustChangePassword: false,
          ),
          services: FieldWorkServices(
            repository: FakeWorkRepository(),
            storage: SembastWorkStorage(
              server: 'https://api.example.com',
              openDatabase: () async => db,
            ),
            taskServices: WorkTaskServices(
              places: () async => smallCatalogue(),
              reader: FakeSerialReader(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await serialTap(tester, 'newWork:repair');
    expect(find.byType(WorkTaskPage), findsOneWidget);
    expect(find.byKey(const ValueKey('takeTaskPhoto:before')), findsOneWidget);
    expect(find.byKey(const ValueKey('taskPhase:after')), findsOneWidget);
  });
  testWidgets(
    'existing old or new QR still requires explicit approval and keeps NTET',
        (tester) async {
      final store = MemoryWorkStore(), repo = FakeWorkRepository();
      await openTask(
        tester,
        WorkDraft(
          id: workId,
          document: WorkDocument(
            kind: WorkKind.replacement,
            schemaVersion: 2,
            progress: 'in_progress',
          ),
        ),
        store,
        repo,
        scannedCode: 'NTET Cd: T0PL0138RO; S/N: 00012',
      );
      await serialTap(tester, 'scanTaskQr:old');
      expect(store.drafts[workId]!.document.oldPole, isNull);
      await serialTap(tester, 'acceptPhotoSerial');
      expect(store.drafts[workId]!.document.oldPole!.serialNumber, '00012');
      expect(store.drafts[workId]!.document.oldPole!.ntetCode, 'T0PL0138RO');
      expect(store.drafts[workId]!.document.oldPole!.source, 'scanned');
    },
  );
  testWidgets(
    'taking a label reads original bytes and requires yes before storing the serial',
        (tester) async {
      final store = MemoryWorkStore(), repo = FakeWorkRepository();
      final reader = FakeSerialReader(
        const SerialReading(
          candidates: [
            SerialCandidate(
              serial: '0002610586',
              source: 'ocr',
              raw: 'Serie: 0002610586',
              score: 100,
            ),
          ],
        ),
      );
      await openTask(
        tester,
        WorkDraft(
          id: workId,
          document: WorkDocument(
            kind: WorkKind.repair,
            schemaVersion: 2,
            progress: 'in_progress',
          ),
        ),
        store,
        repo,
        reader: reader,
      );
      await serialTap(tester, 'takeTaskPhoto:before');
      expect(store.drafts[workId]!.document.oldPole, isNull);
      expect(reader.originals.single, reviewPng);
      await serialTap(tester, 'acceptPhotoSerial');
      final document = store.drafts[workId]!.document;
      expect(document.oldPole!.serialNumber, '0002610586');
      expect(document.oldPole!.confirmed, isTrue);
      expect(document.photos.single.role, 'before');
      expect(document.photos.single.localityCode, '59443');
      expect(repo.sent, isEmpty);
    },
  );
  testWidgets(
    'old overview and separate label can be saved before the new pole exists',
        (tester) async {
      final store = MemoryWorkStore(), repo = FakeWorkRepository();
      await openTask(
        tester,
        WorkDraft(
          id: workId,
          document: WorkDocument(
            kind: WorkKind.replacement,
            schemaVersion: 2,
            progress: 'in_progress',
          ),
        ),
        store,
        repo,
      );
      await serialTap(tester, 'takeTaskPhoto:old');
      await serialTap(tester, 'captureSerialLabel');
      await serialTap(tester, 'serialState:damaged');
      await serialTap(tester, 'acceptPhotoSerial');
      expect(store.drafts[workId]!.document.photos.map((x) => x.role), [
        'old',
        'old_label',
      ]);
      await serialTap(tester, 'saveTaskProgress');
      expect(repo.sent, isEmpty);
      expect(find.text('Save progress'), findsOneWidget);
      await serialTap(tester, 'confirmWorkUpload');
      expect(repo.sent.single.document.progress, 'in_progress');
      expect(repo.sent.single.document.newPole, isNull);
      expect(repo.sent.single.document.oldPole!.serialState, 'damaged');
      expect(store.drafts, isEmpty);
    },
  );
  testWidgets(
    'a downloaded partial replacement resumes at new phase and retains the old photo',
        (tester) async {
      final store = MemoryWorkStore(), repo = FakeWorkRepository();
      final existing = WorkDocument(
        kind: WorkKind.replacement,
        schemaVersion: 2,
        progress: 'in_progress',
        oldPole: confirmedPole(),
        photos: [modernPhoto(role: 'old', local: false)],
      );
      await openTask(
        tester,
        WorkDraft(
          id: workId,
          expectedVersion: versionId,
          reason: 'Continue work',
          document: existing,
        ),
        store,
        repo,
        reader: FakeSerialReader(
          const SerialReading(
            candidates: [
              SerialCandidate(
                serial: '0002610587',
                source: 'ocr',
                raw: 'Serie: 0002610587',
                score: 100,
              ),
            ],
          ),
        ),
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('taskPhase:new')))
            .selected,
        isTrue,
      );
      await serialTap(tester, 'takeTaskPhoto:new');
      await serialTap(tester, 'acceptPhotoSerial');
      await serialTap(tester, 'finishTask');
      await serialTap(tester, 'confirmWorkUpload');
      final sent = repo.sent.single;
      expect(sent.expectedVersion, versionId);
      expect(sent.document.progress, 'completed');
      expect(sent.document.photos.first.id, photoId);
      expect(sent.document.photos.first.isLocal, isFalse);
      expect(sent.document.newPole!.serialNumber, '0002610587');
      expect(sent.document.newPole!.ntetCode, '');
    },
  );
  testWidgets(
    'repair asks whether an empty serial is missing before completion',
        (tester) async {
      final store = MemoryWorkStore(), repo = FakeWorkRepository();
      final document = WorkDocument(
        kind: WorkKind.repair,
        schemaVersion: 2,
        progress: 'in_progress',
        photos: modernDocument(kind: WorkKind.repair).photos,
      );
      await openTask(
        tester,
        WorkDraft(id: workId, document: document),
        store,
        repo,
      );
      await serialTap(tester, 'taskPhase:after');
      await serialTap(tester, 'finishTask');
      expect(repo.sent, isEmpty);
      expect(find.text('Is the serial number correct?'), findsOneWidget);
      await serialTap(tester, 'serialState:missing');
      await serialTap(tester, 'acceptPhotoSerial');
      await serialTap(tester, 'confirmWorkUpload');
      expect(repo.sent.single.document.oldPole!.serialState, 'missing');
      expect(repo.sent.single.document.complete, isTrue);
    },
  );
  testWidgets(
    'retake uses a new photo id and delete removes the selected draft photo',
        (tester) async {
      final store = MemoryWorkStore(), repo = FakeWorkRepository();
      await openTask(
        tester,
        WorkDraft(
          id: workId,
          document: modernDocument(kind: WorkKind.removal),
        ),
        store,
        repo,
      );
      final retake = find.text('Retake');
      await tester.ensureVisible(retake);
      await tester.pumpAndSettle();
      await tester.tap(retake);
      await tester.pumpAndSettle();
      expect(store.drafts[workId]!.document.photos.single.id, isNot(photoId));
      final remove = find.text('Delete').first;
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(store.drafts[workId]!.document.photos, isEmpty);
      expect(repo.sent, isEmpty);
    },
  );
  testWidgets(
    'typing notes keeps the same field and scroll position during local saves',
        (tester) async {
      final store = MemoryWorkStore(), repo = FakeWorkRepository();
      await openTask(
        tester,
        WorkDraft(
          id: workId,
          document: WorkDocument(
            kind: WorkKind.pit,
            schemaVersion: 2,
            progress: 'in_progress',
          ),
        ),
        store,
        repo,
      );
      final notes = find.byKey(const ValueKey('taskNotes'));
      await tester.scrollUntilVisible(
        notes,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(notes);
      await tester.tap(notes);
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(notes);
      final field = tester.widget<TextField>(notes).controller;
      await tester.enterText(notes, 'abc');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(notes).controller, same(field));
      expect((tester.getTopLeft(notes) - before).distance, lessThan(1));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(store.drafts[workId]!.document.notes, 'abc');
    },
  );
  testWidgets(
    'changing type from the second phase resets the phase safely and keeps notes',
        (tester) async {
      final store = MemoryWorkStore(), repo = FakeWorkRepository();
      await openTask(
        tester,
        WorkDraft(
          id: workId,
          expectedVersion: versionId,
          reason: '',
          document: modernDocument().copyWith(notes: 'Keep this note'),
        ),
        store,
        repo,
      );
      await serialTap(tester, 'taskPhase:new');
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change work type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pit'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Change type'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('takeTaskPhoto:pit')), findsOneWidget);
      expect(store.drafts[workId]!.document.photos, isEmpty);
      expect(store.drafts[workId]!.document.notes, 'Keep this note');
      expect(store.drafts[workId]!.reason, '');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a conflicting local draft can be reloaded even if its work type changed elsewhere',
        (tester) async {
      final store = MemoryWorkStore(), repo = FakeWorkRepository();
      await openTask(
        tester,
        WorkDraft(id: workId, document: modernDocument()),
        store,
        repo,
      );
      await serialTap(tester, 'taskPhase:new');
      final saved = store.drafts[workId]!;
      await store.write(
        saved.copyWith(
          document: modernDocument(kind: WorkKind.pit)
              .copyWith(notes: 'Saved elsewhere'),
        ),
      );
      final notes = find.byKey(const ValueKey('taskNotes'));
      await tester.scrollUntilVisible(
        notes,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(notes);
      await tester.pumpAndSettle();
      await tester.enterText(notes, 'Conflicting local edit');
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      final reload = find.widgetWithText(TextButton, 'Load saved draft');
      await tester.ensureVisible(reload);
      await tester.pumpAndSettle();
      await tester.tap(reload);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Load saved draft'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('takeTaskPhoto:pit')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('taskNotes')))
            .controller!
            .text,
        'Saved elsewhere',
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final enabled in [false, true]) {
    testWidgets('new QR generation follows administrator permission $enabled', (
        tester,
        ) async {
      await openTask(
        tester,
        WorkDraft(id: workId, document: modernDocument()),
        MemoryWorkStore(),
        FakeWorkRepository(),
        generation: enabled,
      );
      await serialTap(tester, 'taskPhase:new');
      expect(
        find.byKey(const ValueKey('taskGenerateQr')),
        enabled ? findsOneWidget : findsNothing,
      );
    });
  }
  testWidgets('Romanian task actions stay above the phone navigation buttons', (
      tester,
      ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await openTask(
      tester,
      WorkDraft(
        id: workId,
        document: modernDocument(kind: WorkKind.repair),
      ),
      MemoryWorkStore(),
      FakeWorkRepository(),
      language: 'ro',
    );
    final save = find.byKey(const ValueKey('saveTaskProgress'));
    expect(tester.getBottomRight(save).dy, lessThan(720 - 48));
    expect(tester.takeException(), isNull);
  });
}