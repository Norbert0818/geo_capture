import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/widgets/control_safe_area.dart';
import 'package:geo_capture/features/capture/camera_controls_controller.dart';
import 'package:geo_capture/features/capture/camera_controls_view.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import 'camera_controls_controller_test.dart' show FakeCaptureCamera;

Future<CameraControlsController> showCamera(
    WidgetTester tester,
    CaptureCameraDriver driver, {
      bool enabled = true,
      bool panel = true,
      String language = 'en',
    }) async {
  final controls = CameraControlsController(driver);
  await controls.initialize();
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            CameraGesturePreview(
              controls: controls,
              aspectRatio: .75,
              enabled: enabled,
              child: const ColoredBox(color: Colors.black),
            ),
            if (panel)
              ControlSafeArea(
                child: Column(
                  children: [
                    const Spacer(),
                    CameraControlPanel(controls: controls, enabled: enabled),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('testShutter'),
                      onPressed: () {},
                      child: const Text('Take photo'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controls;
}

void main() {
  late FakeCaptureCamera driver;
  late CameraControlsController controls;
  setUp(() {
    driver = FakeCaptureCamera();
  });
  tearDown(() {
    controls.dispose();
  });

  testWidgets(
    'tapping focuses the cropped preview and shows a temporary marker',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      controls = await showCamera(tester, driver);
      await tester.tapAt(const Offset(100, 400));
      await tester.pump();
      expect(driver.focusPoints, [const Offset(1 / 3, .5)]);
      expect(find.byKey(const ValueKey('cameraFocusMarker')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.byKey(const ValueKey('cameraFocusMarker')), findsNothing);
    },
  );

  testWidgets('two fingers zoom hardware without triggering point focus', (
      tester,
      ) async {
    controls = await showCamera(tester, driver, panel: false);
    final center = tester.getCenter(
      find.byKey(const ValueKey('cameraGestureArea')),
    );
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);
    await first.down(center - const Offset(50, 0));
    await second.down(center + const Offset(50, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(100, 0));
    await second.moveTo(center + const Offset(100, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(controls.zoom, greaterThan(1));
    expect(driver.zooms.last, controls.zoom);
    expect(driver.focusPoints, isEmpty);
  });

  testWidgets('one finger dragging does not change zoom or request focus', (
      tester,
      ) async {
    controls = await showCamera(tester, driver, panel: false);
    await tester.drag(
      find.byKey(const ValueKey('cameraGestureArea')),
      const Offset(100, 0),
    );
    await tester.pumpAndSettle();
    expect(driver.zooms, [1]);
    expect(driver.focusPoints, isEmpty);
  });

  testWidgets('slider changes hardware zoom and the displayed factor', (
      tester,
      ) async {
    controls = await showCamera(tester, driver);
    await tester.drag(
      find.byKey(const ValueKey('cameraZoomSlider')),
      const Offset(50, 0),
    );
    await tester.pumpAndSettle();
    expect(driver.zooms.length, greaterThan(1));
    expect(controls.zoom, greaterThan(1));
    expect(find.text('${controls.zoom.toStringAsFixed(1)}×'), findsOneWidget);
  });

  testWidgets(
    'flash menu applies torch and does not focus the preview behind it',
        (tester) async {
      controls = await showCamera(tester, driver);
      await tester.tap(find.byKey(const ValueKey('cameraFlashMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cameraFlash:torch')));
      await tester.pumpAndSettle();
      expect(controls.flashMode, FlashMode.torch);
      expect(driver.focusPoints, isEmpty);
    },
  );

  testWidgets('auto focus button resets the focus point', (tester) async {
    controls = await showCamera(tester, driver);
    await tester.tap(find.byKey(const ValueKey('cameraAutoFocus')));
    await tester.pumpAndSettle();
    expect(driver.focusPoints, [null]);
  });

  testWidgets('capture disables slider, flash, autofocus and preview taps', (
      tester,
      ) async {
    controls = await showCamera(tester, driver, enabled: false);
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('cameraZoomSlider')))
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<PopupMenuButton<FlashMode>>(
        find.byKey(const ValueKey('cameraFlashMenu')),
      )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('cameraAutoFocus')))
          .onPressed,
      isNull,
    );
    await tester.tapAt(const Offset(200, 200));
    await tester.pumpAndSettle();
    expect(driver.focusPoints, isEmpty);
    expect(find.byKey(const ValueKey('cameraFocusMarker')), findsNothing);
  });

  testWidgets('unsupported focus disables the autofocus action', (
      tester,
      ) async {
    driver.focusPointSupported = false;
    controls = await showCamera(tester, driver);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('cameraAutoFocus')))
          .onPressed,
      isNull,
    );
    expect(find.byTooltip('Tap focus unavailable'), findsOneWidget);
  });

  testWidgets('Romanian flash errors remain local to camera controls', (
      tester,
      ) async {
    driver.rejectedFlashModes.add(FlashMode.torch);
    controls = await showCamera(tester, driver, language: 'ro');
    await tester.tap(find.byKey(const ValueKey('cameraFlashMenu')));
    await tester.pumpAndSettle();
    expect(find.text('Lumină continuă'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cameraFlash:torch')));
    await tester.pumpAndSettle();
    expect(
      find.text('Acest mod de bliț nu este disponibil. Alege alt mod.'),
      findsOneWidget,
    );
    expect(controls.flashMode, FlashMode.off);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('testShutter')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 720), const Size(720, 320)]) {
    testWidgets('controls fit Romanian screen $size above system navigation', (
        tester,
        ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      controls = await showCamera(tester, driver, language: 'ro');
      for (final key in [
        'cameraFlashMenu',
        'cameraZoomSlider',
        'cameraAutoFocus',
        'testShutter',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.bottom, lessThan(size.height - 48));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
      }
      expect(tester.takeException(), isNull);
    });
  }
}