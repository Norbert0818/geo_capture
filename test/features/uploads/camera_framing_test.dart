import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/capture/camera_framing.dart';
import 'package:geo_capture/features/capture/capture_view.dart';
import 'package:geo_capture/features/capture/photo_draft_store.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

Finder key(String name) => find.byKey(ValueKey(name));

void main() {
  test(
    'default framing uses 30 percent above and below, leaving 40 percent clear',
        () {
      const value = CameraFraming();
      expect(value.topPercent, 30);
      expect(value.bottomPercent, 30);
      expect(value.clearPercent, 40);
      expect(value.opacityPercent, 60);
    },
  );

  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final viewport in [const Size(400, 800), const Size(844, 390)]) {
    testWidgets('framing areas use the current full viewport $viewport', (
        tester,
        ) async {
      await size(tester, viewport);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CameraFramingOverlay(framing: CameraFraming())),
        ),
      );
      final top = tester.getRect(key('topFramingShade'));
      final bottom = tester.getRect(key('bottomFramingShade'));
      expect(top.height, closeTo(viewport.height * .3, .01));
      expect(bottom.height, closeTo(viewport.height * .3, .01));
      expect(top.top, 0);
      expect(bottom.bottom, viewport.height);
      expect(bottom.top - top.bottom, closeTo(viewport.height * .4, .01));
    });
  }

  testWidgets('top/bottom sizes and darkness are independent', (tester) async {
    await size(tester, const Size(400, 800));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CameraFramingOverlay(
            framing: CameraFraming(
              topPercent: 20,
              bottomPercent: 35,
              opacityPercent: 75,
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(key('topFramingShade')).height, 160);
    expect(tester.getSize(key('bottomFramingShade')).height, 280);
    expect(tester.widget<ColoredBox>(key('topFramingShade')).color.a, .75);
  });

  testWidgets('shading does not consume camera touches', (tester) async {
    var touches = 0;
    await size(tester, const Size(400, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: () => touches++,
                child: const ColoredBox(color: Colors.teal),
              ),
              const CameraFramingOverlay(framing: CameraFraming()),
            ],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(100, 100));
    expect(touches, 1);
  });

  Future<void> camera(
      WidgetTester tester, {
        Size viewport = const Size(400, 800),
        String language = 'en',
      }) async {
    await size(tester, viewport);
    final drafts = PhotoDraftStore();
    addTearDown(drafts.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CaptureView(
          drafts: drafts,
          onTakePhoto: () {},
          onRetry: () {},
          preview: const ColoredBox(color: Colors.teal),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(key('cameraFramingButton'));
    await tester.pumpAndSettle();
  }

  testWidgets('camera framing controls update the live overlay', (
      tester,
      ) async {
    await camera(tester);
    tester.widget<Slider>(key('topFramingSlider')).onChanged!(45);
    await tester.pumpAndSettle();
    tester.widget<Slider>(key('bottomFramingSlider')).onChanged!(20);
    await tester.pumpAndSettle();
    tester.widget<Slider>(key('framingOpacitySlider')).onChanged!(80);
    await tester.pumpAndSettle();
    final overlay = tester.widget<CameraFramingOverlay>(
      find.byType(CameraFramingOverlay),
    );
    expect(overlay.framing.topPercent, 45);
    expect(overlay.framing.bottomPercent, 20);
    expect(overlay.framing.opacityPercent, 80);
    expect(overlay.framing.clearPercent, 35);
    await tester.ensureVisible(key('closeFramingSettings'));
    await tester.pumpAndSettle();
    await tester.tap(key('closeFramingSettings'));
    await tester.pumpAndSettle();
    expect(tester.getSize(key('topFramingShade')).height, 360);
  });

  testWidgets('reset returns to the configurable defaults', (tester) async {
    await camera(tester);
    tester.widget<Slider>(key('topFramingSlider')).onChanged!(50);
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('resetFramingSettings'));
    await tester.pumpAndSettle();
    await tester.tap(key('resetFramingSettings'));
    await tester.pumpAndSettle();
    expect(find.text('Clear area: 40%'), findsOneWidget);
    expect(
      tester
          .widget<CameraFramingOverlay>(find.byType(CameraFramingOverlay))
          .framing
          .topPercent,
      30,
    );
  });

  testWidgets('a 90 percent band leaves a valid disabled zero-range slider', (
      tester,
      ) async {
    await camera(tester);
    tester.widget<Slider>(key('topFramingSlider')).onChanged!(0);
    await tester.pumpAndSettle();
    tester.widget<Slider>(key('bottomFramingSlider')).onChanged!(90);
    await tester.pumpAndSettle();
    final top = tester.widget<Slider>(key('topFramingSlider'));
    expect(top.value, 0);
    expect(top.max, 0);
    expect(top.onChanged, isNull);
    expect(
      tester
          .widget<CameraFramingOverlay>(find.byType(CameraFramingOverlay))
          .framing
          .clearPercent,
      10,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Romanian framing settings are scrollable in landscape', (
      tester,
      ) async {
    await camera(tester, viewport: const Size(844, 390), language: 'ro');
    expect(find.text('Încadrare cameră'), findsOneWidget);
    await tester.ensureVisible(key('resetFramingSettings'));
    await tester.pumpAndSettle();
    await tester.tap(key('resetFramingSettings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}