import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/models/photo_location.dart';
import 'package:geo_capture/core/widgets/control_safe_area.dart';
import 'package:geo_capture/features/capture/camera_controls_controller.dart';
import 'package:geo_capture/features/capture/camera_controls_view.dart';
import 'package:geo_capture/features/capture/gps_controller.dart';
import 'package:geo_capture/features/capture/gps_status_panel.dart';
import 'package:geo_capture/features/capture/photo_draft.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import 'camera_controls_controller_test.dart' show FakeCaptureCamera;
import 'gps_controller_test.dart' show FakeGpsSource;
import 'gps_quality_test.dart' show gpsNow, gpsFix;

class GpsUiClock {
  DateTime now = gpsNow;
}

class GpsUiRig {
  GpsUiRig(this.source, this.gps, this.cameraDriver, this.camera, this.clock);
  final FakeGpsSource source;
  final GpsController gps;
  final FakeCaptureCamera cameraDriver;
  final CameraControlsController camera;
  final GpsUiClock clock;
  int settingsCalls = 0;
  final captured = <PhotoLocation>[];
  void fix({double accuracy = 3.8}) {
    source.emit(gpsFix(at: clock.now, accuracy: accuracy));
    clock.now = clock.now.add(const Duration(seconds: 1));
  }

  void good() {
    fix();
    fix();
    fix();
  }

  void dispose() {
    gps.dispose();
    camera.dispose();
  }
}

Future<GpsUiRig> showGpsCamera(
    WidgetTester tester, {
      String language = 'en',
      bool? precise = true,
      bool taking = false,
      Object? prepareError,
      bool timer = false,
    }) async {
  // Create the asynchronous controllers inside the widget test's clock zone.
  final clock = GpsUiClock();
  final source = FakeGpsSource()
    ..precise = precise
    ..prepareError = prepareError;
  final gps = GpsController(
    source,
    clock: () => clock.now,
    tickInterval: timer ? const Duration(seconds: 1) : null,
  );
  final driver = FakeCaptureCamera();
  final camera = CameraControlsController(driver);
  final rig = GpsUiRig(source, gps, driver, camera, clock);
  addTearDown(rig.dispose);
  await camera.initialize();
  await gps.start();
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: AnimatedBuilder(
          animation: Listenable.merge([gps, camera]),
          builder: (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              CameraGesturePreview(
                controls: camera,
                aspectRatio: .75,
                enabled: !taking,
                child: const ColoredBox(color: Colors.black),
              ),
              ControlSafeArea(
                child: Column(
                  children: [
                    const SizedBox(
                      height: 48,
                      child: Center(child: Text('Work photo')),
                    ),
                    const Spacer(),
                    GpsCameraControls(
                      gps: gps,
                      camera: camera,
                      enabled: !taking,
                      onRefresh: () {
                        gps.start();
                      },
                      onSettings: () {
                        rig.settingsCalls++;
                      },
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const ValueKey('workShutter'),
                      onPressed: !taking && gps.canCapture && !camera.busy
                          ? () => rig.captured.add(gps.captureLocation())
                          : null,
                      icon: const Icon(Icons.camera_alt),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Take photo'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return rig;
}

bool shutterEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('workShutter')))
        .onPressed !=
        null;

void main() {
  testWidgets(
    'shows acquiring state and no invented accuracy before the first fix',
        (tester) async {
      await showGpsCamera(tester);
      expect(find.text('GPS — m'), findsOneWidget);
      expect(find.text('Acquiring location…'), findsOneWidget);
      expect(shutterEnabled(tester), isFalse);
    },
  );
  testWidgets(
    'three distinct fixes show actual metres and enable the shutter',
        (tester) async {
      final rig = await showGpsCamera(tester);
      rig.fix();
      rig.fix();
      await tester.pump();
      expect(find.text('Good fixes: 2/3'), findsOneWidget);
      expect(shutterEnabled(tester), isFalse);
      rig.fix();
      await tester.pump();
      expect(find.text('GPS ±3.8 m'), findsOneWidget);
      expect(find.text('GPS ready'), findsOneWidget);
      expect(shutterEnabled(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('workShutter')));
      expect(rig.captured.single.accuracyMeters, 3.8);
    },
  );
  testWidgets('weaker latest measurement disables a previously ready shutter', (
      tester,
      ) async {
    final rig = await showGpsCamera(tester);
    rig.good();
    await tester.pump();
    expect(shutterEnabled(tester), isTrue);
    rig.fix(accuracy: 12);
    await tester.pump();
    expect(find.text('GPS ±12.0 m'), findsOneWidget);
    expect(find.text('Waiting for ≤5.0 m'), findsOneWidget);
    expect(shutterEnabled(tester), isFalse);
  });
  testWidgets(
    'measure again discards the old measurement and requires new fixes',
        (tester) async {
      final rig = await showGpsCamera(tester);
      rig.good();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('refreshGps')));
      await tester.pumpAndSettle();
      // Stream cancellation can complete outside the fake animation clock.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      for (var attempt = 0; attempt < 10 && rig.gps.starting; attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(rig.gps.starting, isFalse);
      expect(rig.source.cancellations, 1);
      expect(find.text('GPS — m'), findsOneWidget);
      expect(shutterEnabled(tester), isFalse);
      rig.good();
      await tester.pump();
      expect(shutterEnabled(tester), isTrue);
    },
  );
  testWidgets(
    'approximate permission shows Romanian guidance and a settings action',
        (tester) async {
      final rig = await showGpsCamera(tester, language: 'ro', precise: false);
      rig.good();
      await tester.pump();
      expect(find.text('Activează locația precisă'), findsOneWidget);
      expect(find.byTooltip('Setări locație'), findsOneWidget);
      expect(shutterEnabled(tester), isFalse);
      await tester.tap(find.byKey(const ValueKey('gpsSettings')));
      expect(rig.settingsCalls, 1);
    },
  );
  testWidgets(
    'disabled location service remains actionable with the camera visible',
        (tester) async {
      await showGpsCamera(
        tester,
        prepareError: const CaptureException('location_disabled'),
      );
      expect(find.text('Turn on location services'), findsOneWidget);
      expect(find.byKey(const ValueKey('cameraZoomSlider')), findsOneWidget);
      expect(find.byKey(const ValueKey('gpsSettings')), findsOneWidget);
      expect(shutterEnabled(tester), isFalse);
    },
  );
  testWidgets(
    'accuracy changes do not move the controls or shutter vertically',
        (tester) async {
      final rig = await showGpsCamera(tester);
      final initialPanel = tester.getRect(
        find.byKey(const ValueKey('gpsStatusPanel')),
      );
      final initialShutter = tester.getRect(
        find.byKey(const ValueKey('workShutter')),
      );
      rig.good();
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('gpsStatusPanel'))),
        initialPanel,
      );
      rig.fix(accuracy: 50);
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('gpsStatusPanel'))),
        initialPanel,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('workShutter'))),
        initialShutter,
      );
    },
  );
  testWidgets(
    'the timer invalidates stale measurements without a new sensor event',
        (tester) async {
      final rig = await showGpsCamera(tester, timer: true);
      rig.good();
      await tester.pump();
      expect(shutterEnabled(tester), isTrue);
      rig.clock.now = rig.clock.now.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Location expired. Measure again.'), findsOneWidget);
      expect(shutterEnabled(tester), isFalse);
    },
  );
  testWidgets('focus remains touchable while GPS is acquiring a position', (
      tester,
      ) async {
    final rig = await showGpsCamera(tester);
    final area = tester.getRect(
      find.byKey(const ValueKey('cameraGestureArea')),
    );
    await tester.tapAt(Offset(area.center.dx, area.top + 130));
    await tester.pumpAndSettle();
    expect(rig.cameraDriver.focusPoints, hasLength(1));
    expect(shutterEnabled(tester), isFalse);
    await tester.pump(const Duration(milliseconds: 1300));
  });
  testWidgets('unknown zero accuracy is never displayed as perfect GPS', (
      tester,
      ) async {
    final rig = await showGpsCamera(tester);
    rig.fix(accuracy: 0);
    await tester.pump();
    expect(find.text('GPS — m'), findsOneWidget);
    expect(find.text('GPS ±0.0 m'), findsNothing);
    expect(shutterEnabled(tester), isFalse);
  });
  testWidgets('capture disables remeasurement, settings and hardware changes', (
      tester,
      ) async {
    await showGpsCamera(tester, precise: false, taking: true);
    for (final key in ['refreshGps', 'gpsSettings', 'cameraAutoFocus']) {
      expect(
        tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
      );
    }
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('cameraZoomSlider')))
          .onChanged,
      isNull,
    );
  });
  for (final size in [const Size(320, 720), const Size(720, 320)]) {
    testWidgets('GPS and camera controls fit $size above Android navigation', (
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
      await showGpsCamera(tester, precise: false, language: 'ro');
      for (final key in [
        'gpsStatusPanel',
        'refreshGps',
        'gpsSettings',
        'cameraFlashMenu',
        'cameraZoomSlider',
        'cameraAutoFocus',
        'workShutter',
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