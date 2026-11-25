import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/models/session_user.dart';
import 'package:geo_capture/core/models/photo_location.dart';
import 'package:geo_capture/features/capture/photo_draft.dart';
import 'package:geo_capture/features/field_work/work_editor_page.dart';
import 'package:geo_capture/features/field_work/work_home_page.dart';
import 'package:geo_capture/features/field_work/work_identity_editor.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_stamp_service.dart';
import 'package:geo_capture/features/field_work/work_storage.dart';
import 'package:geo_capture/l10n/app_localizations.dart';
import 'package:sembast/sembast_memory.dart';

import 'work_test_support.dart';

void main() {
  Widget shell(Widget child, {String locale = 'en'}) => MaterialApp(
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );

  testWidgets('home offers all four work types before starting a camera', (
      tester,
      ) async {
    final db = await databaseFactoryMemory.openDatabase('home-test');
    addTearDown(db.close);
    await tester.pumpWidget(
      shell(
        WorkHomePage(
          services: FieldWorkServices(
            repository: FakeWorkRepository(),
            storage: SembastWorkStorage(
              server: 'https://api.example.com',
              openDatabase: () async => db,
            ),
          ),
          user: SessionUser(
            id: workId,
            username: 'worker',
            roles: ['User'],
            mustChangePassword: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final kind in WorkKind.values) {
      expect(find.byKey(ValueKey('newWork:${kind.name}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('allowWorkQrGeneration')), findsNothing);
    expect(find.byKey(const ValueKey('workShutter')), findsNothing);
  });

  testWidgets('admin can switch generation on and off', (tester) async {
    final db = await databaseFactoryMemory.openDatabase('admin-test');
    addTearDown(db.close);
    final repo = FakeWorkRepository();
    await tester.pumpWidget(
      shell(
        WorkHomePage(
          services: FieldWorkServices(
            repository: repo,
            storage: SembastWorkStorage(
              server: 'https://api.example.com',
              openDatabase: () async => db,
            ),
          ),
          user: SessionUser(
            id: workId,
            username: 'admin',
            roles: ['Admin'],
            mustChangePassword: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('allowWorkQrGeneration'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(repo.current.allowQrGeneration, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(repo.current.allowQrGeneration, isFalse);
  });

  testWidgets('QR generation button follows the admin setting', (tester) async {
    for (final allowed in [false, true]) {
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: WorkIdentityEditor(
              key: ValueKey(allowed),
              value: const PoleIdentity(
                serialNumber: '0009',
                ntetCode: 'T0PL0138RO',
              ),
              onChanged: (_) {},
              isNewPole: true,
              allowGeneration: allowed,
              enabled: true,
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('generatePoleQr')),
        allowed ? findsOneWidget : findsNothing,
      );
    }
  });

  for (final kind in WorkKind.values) {
    testWidgets('${kind.name} begins with the requested first step', (
        tester,
        ) async {
      final store = MemoryWorkStore();
      await tester.pumpWidget(
        shell(
          WorkEditorPage(
            draft: WorkDraft(
              id: workId,
              document: WorkDocument(kind: kind),
            ),
            store: store,
            repository: FakeWorkRepository(),
            allowGeneration: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (kind == WorkKind.replacement || kind == WorkKind.removal) {
        expect(find.byType(WorkIdentityEditor), findsOneWidget);
        expect(
          find.byKey(ValueKey('takeWorkPhoto:${workRoles[kind]!.first}')),
          findsNothing,
        );
      } else {
        expect(find.byType(WorkIdentityEditor), findsNothing);
        expect(
          find.byKey(ValueKey('takeWorkPhoto:${workRoles[kind]!.first}')),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets(
    'repair cannot advance to the serial step without the before photo',
        (tester) async {
      final store = MemoryWorkStore();
      await tester.pumpWidget(
        shell(
          WorkEditorPage(
            draft: WorkDraft(
              id: workId,
              document: WorkDocument(kind: WorkKind.repair),
            ),
            store: store,
            repository: FakeWorkRepository(),
            allowGeneration: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('workContinue')))
            .onPressed,
        isNull,
      );
      expect(find.text('Existing / old pole serial number'), findsNothing);
    },
  );

  testWidgets('a restored frozen upload can be retried from the first step', (
      tester,
      ) async {
    final store = MemoryWorkStore();
    final draft = WorkDraft(
      id: workId,
      document: sampleWorkDocument(kind: WorkKind.replacement),
      pendingChangeId: versionId,
    );
    final revision = await store.write(draft);
    final repo = FakeWorkRepository();
    await tester.pumpWidget(
      shell(
        WorkEditorPage(
          draft: draft.copyWith(localRevision: revision),
          store: store,
          repository: repo,
          allowGeneration: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry pending upload'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      isFalse,
    );
  });

  testWidgets(
    'Romanian workflow remains usable on a narrow phone with navigation insets',
        (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpWidget(
        shell(
          WorkEditorPage(
            draft: WorkDraft(
              id: workId,
              document: WorkDocument(kind: WorkKind.pit),
            ),
            store: MemoryWorkStore(),
            repository: FakeWorkRepository(),
            allowGeneration: false,
          ),
          locale: 'ro',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Groapă'), findsOneWidget);
      final button = find.byKey(const ValueKey('takeWorkPhoto:pit'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(button).dy, lessThan(720 - 48));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'old pole photo must be confirmed and a rejected image can be retaken',
        (tester) async {
      final store = MemoryWorkStore();
      var captures = 0;
      final png = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAIAAADkharWAAAAF0lEQVR4nGN0y5vGQApgIkn1qIYRpAEAER0BYmrANbUAAAAASUVORK5CYII=',
        ),
      );
      final doc = WorkDocument(
        kind: WorkKind.replacement,
        oldPole: const PoleIdentity(serialNumber: '2610586'),
      );
      await tester.pumpWidget(
        shell(
          WorkEditorPage(
            draft: WorkDraft(id: workId, document: doc),
            store: store,
            repository: FakeWorkRepository(),
            allowGeneration: false,
            capturePhoto: (_, _) async {
              captures++;
              final now = DateTime.now().toUtc();
              return PhotoDraft(
                id: captures == 1 ? photoId : versionId,
                originalBytes: png,
                mimeType: 'image/png',
                capturedAt: now,
                location: PhotoLocation(
                  latitude: 46.77,
                  longitude: 24.3,
                  accuracyMeters: 4,
                  measuredAt: now,
                ),
              );
            },
            lookupPlace: (_) async => const WorkPlace('Sâncraiu', 'Cluj'),
            stampPhoto: (photo, original) async =>
                photo.withBytes(original, original),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workContinue')));
      await tester.pumpAndSettle();
      final shutter = find.byKey(const ValueKey('takeWorkPhoto:old'));
      await tester.ensureVisible(shutter);
      await tester.tap(shutter);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text(
          'Is the old pole serial number clearly visible in this photo?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('No / retake'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(captures, 2);
      await tester.tap(find.text('Yes'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Use on photo'));
      await tester.pumpAndSettle();
      final saved = store.drafts[workId]!.document.photos.single;
      expect(saved.id, versionId);
      expect(saved.serialVisible, isTrue);
      expect(saved.locality, 'Sâncraiu');
      expect(find.text('Retake photo'), findsOneWidget);
      expect(find.text('Delete photo'), findsOneWidget);
    },
  );
}
