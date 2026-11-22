import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/capture/photo_draft_store.dart';
import 'package:geo_capture/features/uploads/upload_batch.dart';
import 'package:geo_capture/features/uploads/upload_controller.dart';
import 'package:geo_capture/features/uploads/upload_history_models.dart';
import 'package:geo_capture/features/uploads/upload_history_page.dart';
import 'package:geo_capture/features/uploads/upload_panel.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import 'history_test_support.dart';
import 'upload_test_support.dart';

Finder key(String name) => find.byKey(ValueKey(name));

void main() {
  UploadBatch batch({String old = ' 0001 ', String next = ' 0002 '}) =>
      UploadBatch.create(
        oldSerialNumber: old,
        newSerialNumber: next,
        photos: [photo(1)],
        limits: limits,
      );

  test('both serials remain text and preserve leading zeros', () {
    final value = batch();
    expect(value.oldSerialNumber, '0001');
    expect(value.newSerialNumber, '0002');
    expect(value.manifest['oldSerialNumber'], '0001');
    expect(value.manifest['newSerialNumber'], '0002');
    expect(value.manifest.containsKey('serialNumber'), isFalse);
  });

  for (final old in [true, false]) {
    for (final value in [
      '',
      '   ',
      'bad\nserial',
      List.filled(257, 'X').join(),
    ]) {
      test(
        'rejects ${old ? 'old' : 'new'} serial ${value.length} characters',
            () {
          expect(
                () => old ? batch(old: value) : batch(next: value),
            throwsA(
              isA<ApiException>().having(
                    (e) => e.code,
                'code',
                old ? 'invalid_old_serial_number' : 'invalid_new_serial_number',
              ),
            ),
          );
        },
      );
    }
  }

  test('a different old serial in a server confirmation does not confirm the batch', () {
    final value = batch();
    final receipt = UploadReceipt.fromJson(
      receiptJson(value)..['oldSerialNumber'] = 'OTHER',
    );
    expect(receipt.confirms(value), isFalse);
  });

  test('a pending retry retains both serials and the same batch id', () async {
    final drafts = PhotoDraftStore();
    final repository = FakeUploadRepository();
    final controller = UploadController(drafts: drafts, repository: repository);
    addTearDown(controller.dispose);
    addTearDown(drafts.dispose);
    await controller.loadLimits();
    await drafts.capture(() async => photo(1));
    repository.onUpload = (_) async =>
    throw const ApiException('service_unavailable');
    await controller.submit(oldSerialNumber: '0001', newSerialNumber: '0002');
    final first = controller.pendingBatch!;
    repository.onUpload = (value) async => receiptFor(value, replayed: true);
    await controller.submit(
      oldSerialNumber: 'CHANGED-OLD',
      newSerialNumber: 'CHANGED-NEW',
    );
    expect(repository.batches.last.id, first.id);
    expect(repository.batches.last.oldSerialNumber, '0001');
    expect(repository.batches.last.newSerialNumber, '0002');
    expect(drafts.items, isEmpty);
  });

  test('legacy history does not invent an old/new pair', () {
    final item = UploadHistoryItem.fromJson(summaryJson(1));
    expect(item.serialNumber, '0001 / AB');
    expect(item.hasSerialPair, isFalse);
    expect(item.oldSerialNumber, isNull);
    expect(item.newSerialNumber, isNull);
  });

  test('a partially returned serial pair is rejected', () {
    expect(
          () => UploadHistoryItem.fromJson(
        summaryJson(1)..['oldSerialNumber'] = 'OLD',
      ),
      throwsFormatException,
    );
  });

  Widget app(Widget child, {String language = 'en'}) => MaterialApp(
    locale: Locale(language),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  testWidgets('both input fields are mandatory before uploading', (
      tester,
      ) async {
    final drafts = PhotoDraftStore();
    final repository = FakeUploadRepository();
    final controller = UploadController(drafts: drafts, repository: repository);
    addTearDown(controller.dispose);
    addTearDown(drafts.dispose);
    await drafts.capture(() async => photo(1));
    await tester.pumpWidget(
      app(Scaffold(body: UploadPanel(controller: controller))),
    );
    await tester.tap(key('uploadPhotosButton'));
    await tester.pumpAndSettle();
    await tester.enterText(key('newSerialNumberField'), '0002');
    await tester.tap(key('confirmUploadButton'));
    await tester.pumpAndSettle();
    expect(repository.batches, isEmpty);
    await tester.enterText(key('oldSerialNumberField'), '0001');
    await tester.enterText(key('newSerialNumberField'), '');
    await tester.tap(key('confirmUploadButton'));
    await tester.pumpAndSettle();
    expect(repository.batches, isEmpty);
    await tester.enterText(key('newSerialNumberField'), '0002');
    await tester.tap(key('confirmUploadButton'));
    await tester.pumpAndSettle();
    expect(repository.batches.single.oldSerialNumber, '0001');
    expect(repository.batches.single.newSerialNumber, '0002');
  });

  for (final allUsers in [false, true]) {
    testWidgets('history shows both serial labels: admin list=$allUsers', (
        tester,
        ) async {
      final repository = FakeHistoryRepository();
      repository.onList = (_, _, _) async => UploadHistoryResult.fromJson({
        ...pageJson(total: 1),
        'items': [
          {
            ...summaryJson(1),
            'oldSerialNumber': 'OLD-0001',
            'newSerialNumber': '0001 / AB',
          },
        ],
      });
      await tester.pumpWidget(
        app(UploadHistoryPage(repository: repository, allUsers: allUsers)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old serial number: OLD-0001'), findsOneWidget);
      expect(find.text('New serial number: 0001 / AB'), findsOneWidget);
      expect(repository.lists.single.allUsers, allUsers);
    });
  }

  testWidgets('Romanian form labels distinguish old and new', (tester) async {
    await tester.pumpWidget(
      app(
        const Scaffold(body: SerialNumberDialog(limits: limits)),
        language: 'ro',
      ),
    );
    expect(find.text('Număr de serie vechi'), findsOneWidget);
    expect(find.text('Număr de serie nou'), findsOneWidget);
  });
}