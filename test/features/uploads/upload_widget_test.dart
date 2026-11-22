import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/capture/photo_draft_store.dart';
import 'package:geo_capture/features/uploads/upload_batch.dart';
import 'package:geo_capture/features/uploads/upload_controller.dart';
import 'package:geo_capture/features/uploads/upload_panel.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import 'upload_test_support.dart';

Finder key(String value) => find.byKey(ValueKey(value));

void main() {
  late PhotoDraftStore drafts;
  late FakeUploadRepository repository;
  late UploadController controller;

  setUp(() {
    drafts = PhotoDraftStore();
    repository = FakeUploadRepository();
    controller = UploadController(drafts: drafts, repository: repository);
  });
  tearDown(() {
    controller.dispose();
    drafts.dispose();
  });

  Future<void> start(WidgetTester tester, {String language = 'en'}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: UploadPanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(key('uploadPhotosButton'));
    await tester.pumpAndSettle();
  }

  testWidgets('upload is disabled when no photos are waiting', (tester) async {
    await start(tester);
    expect(
      tester.widget<FilledButton>(key('uploadPhotosButton')).onPressed,
      isNull,
    );
    expect(repository.batches, isEmpty);
  });

  testWidgets('canceling the serial dialog does not upload or remove photos', (
      tester,
      ) async {
    await drafts.capture(() async => photo(1));
    await start(tester);
    await open(tester);
    expect(key('newSerialNumberField'), findsOneWidget);
    await tester.tap(key('cancelUploadButton'));
    await tester.pumpAndSettle();
    expect(repository.batches, isEmpty);
    expect(drafts.items, hasLength(1));
  });

  testWidgets(
    'empty serial stays in the dialog and a valid serial keeps zeros',
        (tester) async {
      await drafts.capture(() async => photo(1));
      await start(tester);
      await open(tester);
      await tester.tap(key('confirmUploadButton'));
      await tester.pumpAndSettle();
      expect(key('newSerialNumberField'), findsOneWidget);
      expect(repository.batches, isEmpty);
      await tester.enterText(key('oldSerialNumberField'), 'OLD');
      await tester.enterText(key('newSerialNumberField'), '000123');
      await tester.tap(key('confirmUploadButton'));
      await tester.pumpAndSettle();
      expect(repository.batches.single.newSerialNumber, '000123');
      expect(key('uploadSuccess'), findsOneWidget);
      expect(drafts.items, isEmpty);
    },
  );

  testWidgets(
    'Romanian dialog and success message follow the selected locale',
        (tester) async {
      await drafts.capture(() async => photo(1));
      await start(tester, language: 'ro');
      expect(find.text('Încarcă fotografiile'), findsOneWidget);
      await open(tester);
      expect(find.text('Anulează'), findsOneWidget);
      await tester.enterText(key('oldSerialNumberField'), 'OLD');
      await tester.enterText(key('newSerialNumberField'), 'RO-001');
      await tester.tap(key('confirmUploadButton'));
      await tester.pumpAndSettle();
      expect(find.text('Încărcare salvată'), findsOneWidget);
    },
  );

  testWidgets('failure retries without opening another serial dialog', (
      tester,
      ) async {
    await drafts.capture(() async => photo(1));
    repository.onUpload = (_) async =>
    throw const ApiException('service_unavailable');
    await start(tester);
    await open(tester);
    await tester.enterText(key('oldSerialNumberField'), 'OLD');
    await tester.enterText(key('newSerialNumberField'), 'A-0001');
    await tester.tap(key('confirmUploadButton'));
    await tester.pumpAndSettle();
    expect(key('uploadError'), findsOneWidget);
    expect(find.text('Retry upload'), findsOneWidget);
    final first = repository.batches.single;
    repository.onUpload = (batch) async => receiptFor(batch, replayed: true);
    await tester.tap(key('uploadPhotosButton'));
    await tester.pumpAndSettle();
    expect(key('newSerialNumberField'), findsNothing);
    expect(repository.batches.last.id, first.id);
    expect(key('uploadSuccess'), findsOneWidget);
  });

  testWidgets('waiting for server confirmation does not show success', (
      tester,
      ) async {
    await drafts.capture(() async => photo(1));
    final result = Completer<UploadReceipt>();
    repository.onUpload = (_) => result.future;
    await start(tester);
    await open(tester);
    await tester.enterText(key('oldSerialNumberField'), 'OLD');
    await tester.enterText(key('newSerialNumberField'), 'A');
    await tester.tap(key('confirmUploadButton'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    repository.progress!(100, 100);
    await tester.pump();
    expect(find.text('Waiting for confirmation...'), findsOneWidget);
    expect(key('uploadSuccess'), findsNothing);
    expect(drafts.items, hasLength(1));
    result.complete(receiptFor(repository.batches.single));
    await tester.pumpAndSettle();
    expect(key('uploadSuccess'), findsOneWidget);
  });
}