import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/capture/capture_view.dart';
import 'package:geo_capture/features/capture/photo_draft_store.dart';
import 'package:geo_capture/features/uploads/upload_controller.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import '../uploads/upload_test_support.dart';

Finder key(String value) => find.byKey(ValueKey(value));

void main() {
  late PhotoDraftStore drafts;
  late UploadController uploads;
  late FakeUploadRepository repository;

  setUp(() {
    drafts = PhotoDraftStore();
    repository = FakeUploadRepository();
    uploads = UploadController(drafts: drafts, repository: repository);
  });
  tearDown(() {
    uploads.dispose();
    drafts.dispose();
  });

  Future<void> start(
      WidgetTester tester, {
        Size size = const Size(400, 800),
        EdgeInsets system = const EdgeInsets.only(top: 24, bottom: 48),
        EdgeInsets gestures = EdgeInsets.zero,
        double keyboard = 0,
        double textScale = 1,
        String language = 'en',
        String? cameraError,
        VoidCallback? retry,
      }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: system.copyWith(
              bottom: math.max(0, system.bottom - keyboard),
            ),
            viewPadding: system,
            systemGestureInsets: gestures,
            viewInsets: EdgeInsets.only(bottom: keyboard),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: CaptureView(
          preview: const ColoredBox(color: Colors.teal),
          drafts: drafts,
          uploads: uploads,
          onTakePhoto: () => drafts.capture(() async => photo(9)),
          cameraReady: cameraError == null,
          cameraError: cameraError,
          onRetry: retry ?? () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'all bottom camera controls sit 24 dp above three-button navigation',
        (tester) async {
      await start(tester);
      for (final name in [
        'reviewPhotosButton',
        'takePhotoButton',
        'openUploadButton',
      ]) {
        expect(
          tester.getRect(key(name)).bottom,
          lessThanOrEqualTo(800 - 48 - 24),
        );
      }
      expect(tester.getSize(key('cameraViewport')), const Size(400, 800));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'gesture navigation keeps all camera touch targets away from the edges',
        (tester) async {
      await start(
        tester,
        system: const EdgeInsets.only(top: 24, bottom: 20),
        gestures: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      );
      for (final name in [
        'reviewPhotosButton',
        'takePhotoButton',
        'openUploadButton',
      ]) {
        final rect = tester.getRect(key(name));
        expect(rect.bottom, lessThanOrEqualTo(800 - 32 - 24));
        expect(rect.left, greaterThanOrEqualTo(24 + 16));
        expect(rect.right, lessThanOrEqualTo(400 - 24 - 16));
      }
      expect(
        tester.getRect(key('closeCameraButton')).top,
        greaterThanOrEqualTo(36),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'landscape side navigation and display cutout protect the controls',
        (tester) async {
      await start(
        tester,
        size: const Size(844, 390),
        system: const EdgeInsets.fromLTRB(32, 0, 48, 0),
      );
      for (final name in [
        'closeCameraButton',
        'reviewPhotosButton',
        'takePhotoButton',
        'openUploadButton',
      ]) {
        final rect = tester.getRect(key(name));
        expect(rect.left, greaterThanOrEqualTo(32 + 16));
        expect(rect.right, lessThanOrEqualTo(844 - 48 - 16));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a short error screen can scroll to every camera control', (
      tester,
      ) async {
    var retries = 0;
    await start(
      tester,
      size: const Size(568, 240),
      textScale: 1.5,
      language: 'ro',
      cameraError: 'camera_unavailable',
      retry: () => retries++,
    );
    for (final name in [
      'closeCameraButton',
      'retryCameraButton',
      'reviewPhotosButton',
    ]) {
      await tester.ensureVisible(key(name));
      await tester.pumpAndSettle();
      final rect = tester.getRect(key(name));
      expect(rect.top, greaterThanOrEqualTo(24 + 12 - .01));
      expect(rect.bottom, lessThanOrEqualTo(240 - 48 - 24 + .01));
      if (name == 'retryCameraButton') await tester.tap(key(name));
    }
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'larger Romanian text keeps the bottom buttons above the system bar',
        (tester) async {
      await start(
        tester,
        size: const Size(320, 568),
        language: 'ro',
        textScale: 1.8,
      );
      await tester.ensureVisible(key('reviewPhotosButton'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(key('reviewPhotosButton')).bottom,
        lessThanOrEqualTo(568 - 48 - 24),
      );
      expect(
        tester.getRect(key('openUploadButton')).bottom,
        lessThanOrEqualTo(568 - 48 - 24),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the last photo delete action remains reachable above navigation',
        (tester) async {
      await drafts.capture(() async => photo(1));
      await drafts.capture(() async => photo(2));
      final id = drafts.items.last.id;
      await start(tester);
      await tester.tap(key('reviewPhotosButton'));
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: key('photoReviewList'),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(id)),
        300,
        scrollable: list.first,
      );
      final remove = find.descendant(
        of: find.byKey(ValueKey(id)),
        matching: find.byTooltip('Remove photo'),
      );
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      expect(tester.getRect(remove).bottom, lessThanOrEqualTo(800 - 48 - 24));
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(drafts.items.map((photo) => photo.id), isNot(contains(id)));
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(400, 800), const Size(844, 390)]) {
    testWidgets('serial confirmation is reachable with a keyboard at $size', (
        tester,
        ) async {
      final landscape = size.width > size.height;
      final keyboard = landscape ? 180.0 : 300.0;
      await drafts.capture(() async => photo(1));
      await start(
        tester,
        size: size,
        system: landscape
            ? const EdgeInsets.fromLTRB(0, 24, 48, 0)
            : const EdgeInsets.only(top: 24, bottom: 48),
        keyboard: keyboard,
        language: 'ro',
        textScale: 1.2,
      );
      await tester.tap(key('openUploadButton'));
      await tester.pumpAndSettle();
      expect(key('serialNumberField'), findsOneWidget);
      await tester.ensureVisible(key('serialNumberField'));
      await tester.pumpAndSettle();
      await tester.enterText(key('serialNumberField'), '00042');
      final confirm = key('confirmUploadButton');
      expect(
        tester.getRect(confirm).bottom,
        lessThanOrEqualTo(size.height - keyboard),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repository.batches.single.serialNumber, '00042');
      expect(drafts.items, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}