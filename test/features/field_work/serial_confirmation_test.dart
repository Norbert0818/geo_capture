import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/field_work/serial_confirmation.dart';
import 'package:geo_capture/features/field_work/serial_reading.dart';

import 'modern_work_test_support.dart';
import 'work_flow_test.dart' show reviewPng;
import 'work_test_support.dart';

Future<List<SerialDecision?>> openSerial(
    WidgetTester tester, {
      SerialReading reading = const SerialReading(),
      String language = 'en',
    }) async {
  final result = <SerialDecision?>[];
  await tester.pumpWidget(
    modernShell(
      Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => result.add(
              await confirmPhotoSerial(
                context,
                reading: reading,
                image: reviewPng,
                photoId: photoId,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      language: language,
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> serialTap(WidgetTester tester, String key) async {
  final item = find.byKey(ValueKey(key));
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a recognized number is saved only after explicit approval', (
      tester,
      ) async {
    final result = await openSerial(
      tester,
      reading: const SerialReading(
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
    expect(result, isEmpty);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('confirmSerialNumber')))
          .controller!
          .text,
      '0002610586',
    );
    await serialTap(tester, 'acceptPhotoSerial');
    expect(result.single!.identity!.serialNumber, '0002610586');
    expect(result.single!.identity!.confirmed, isTrue);
    expect(result.single!.identity!.evidencePhotoId, photoId);
    expect(result.single!.identity!.source, 'ocr');
  });
  testWidgets('No edit accepts only digits and preserves zeros', (
      tester,
      ) async {
    final result = await openSerial(
      tester,
      reading: const SerialReading(
        candidates: [
          SerialCandidate(
            serial: '1234',
            source: 'ocr',
            raw: 'Serie:1234',
            score: 100,
          ),
        ],
      ),
    );
    await serialTap(tester, 'editReadSerial');
    await tester.enterText(
      find.byKey(const ValueKey('confirmSerialNumber')),
      '00a00 17',
    );
    await serialTap(tester, 'acceptPhotoSerial');
    expect(result.single!.identity!.serialNumber, '000017');
    expect(result.single!.identity!.source, 'manual');
  });
  testWidgets('unresolved serial cannot be silently skipped as absent', (
      tester,
      ) async {
    final result = await openSerial(tester);
    await serialTap(tester, 'acceptPhotoSerial');
    expect(result, isEmpty);
    expect(
      find.byKey(const ValueKey('serialConfirmationError')),
      findsOneWidget,
    );
  });
  for (final state in ['missing', 'damaged']) {
    testWidgets('$state is an explicit valid decision without a number', (
        tester,
        ) async {
      final result = await openSerial(tester);
      await serialTap(tester, 'serialState:$state');
      await serialTap(tester, 'acceptPhotoSerial');
      expect(result.single!.identity!.serialState, state);
      expect(result.single!.identity!.serialNumber, '');
      expect(result.single!.identity!.confirmed, isTrue);
    });
  }
  testWidgets('conflicting OCR QR readings do not prefill or select a number', (
      tester,
      ) async {
    final result = await openSerial(
      tester,
      reading: const SerialReading(
        candidates: [
          SerialCandidate(
            serial: '00012',
            source: 'scanned',
            raw: '00012',
            score: 110,
          ),
          SerialCandidate(
            serial: '00013',
            source: 'ocr',
            raw: 'Serie: 00013',
            score: 100,
          ),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('confirmSerialNumber')), findsNothing);
    await serialTap(tester, 'serialCandidate:00013');
    await serialTap(tester, 'acceptPhotoSerial');
    expect(result.single!.identity!.serialNumber, '00013');
  });
  testWidgets(
    'a dedicated label photo can be requested without accepting guessed data',
        (tester) async {
      final result = await openSerial(tester);
      await serialTap(tester, 'captureSerialLabel');
      expect(result.single!.takeLabel, isTrue);
      expect(result.single!.identity, isNull);
    },
  );
  testWidgets(
    'Romanian correction dialog fits a small phone and keyboard insets',
        (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await openSerial(tester, language: 'ro');
      await serialTap(tester, 'editReadSerial');
      await tester.enterText(
        find.byKey(const ValueKey('confirmSerialNumber')),
        '0001234',
      );
      await serialTap(tester, 'acceptPhotoSerial');
      expect(tester.takeException(), isNull);
    },
  );
}