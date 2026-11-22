import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/widgets/control_safe_area.dart';

const contentKey = ValueKey('protectedContent');

void main() {
  Future<void> start(
      WidgetTester tester,
      MediaQueryData data, {
        Widget? content,
      }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: data,
          child: ControlSafeArea(
            child: content ?? const SizedBox.expand(key: contentKey),
          ),
        ),
      ),
    );
  }

  testWidgets('button navigation receives extra space above the system bar', (
      tester,
      ) async {
    await start(
      tester,
      const MediaQueryData(
        padding: EdgeInsets.only(top: 32, bottom: 48),
        viewPadding: EdgeInsets.only(top: 32, bottom: 48),
      ),
    );
    expect(
      tester.getRect(find.byKey(contentKey)),
      const Rect.fromLTRB(16, 44, 384, 728),
    );
  });

  testWidgets('gesture-only insets also protect the sides and bottom', (
      tester,
      ) async {
    await start(
      tester,
      const MediaQueryData(
        padding: EdgeInsets.only(top: 24, bottom: 20),
        viewPadding: EdgeInsets.only(top: 24, bottom: 20),
        systemGestureInsets: EdgeInsets.fromLTRB(24, 0, 24, 32),
      ),
    );
    expect(
      tester.getRect(find.byKey(contentKey)),
      const Rect.fromLTRB(40, 36, 360, 744),
    );
  });

  testWidgets('keyboard appearance preserves the system bar reserve', (
      tester,
      ) async {
    late MediaQueryData inside;
    await start(
      tester,
      const MediaQueryData(
        padding: EdgeInsets.only(top: 24),
        viewPadding: EdgeInsets.only(top: 24, bottom: 48),
        viewInsets: EdgeInsets.only(bottom: 300),
      ),
      content: Builder(
        builder: (context) {
          inside = MediaQuery.of(context);
          return const SizedBox.expand(key: contentKey);
        },
      ),
    );
    expect(tester.getRect(find.byKey(contentKey)).bottom, 728);
    expect(inside.viewInsets.bottom, 300);
    expect(inside.viewPadding.bottom, 0);
  });

  testWidgets('nested content does not consume the system insets twice', (
      tester,
      ) async {
    await start(
      tester,
      const MediaQueryData(
        padding: EdgeInsets.only(top: 24, bottom: 48),
        viewPadding: EdgeInsets.only(top: 24, bottom: 48),
        systemGestureInsets: EdgeInsets.fromLTRB(24, 0, 24, 32),
      ),
      content: const ControlSafeArea(
        spacing: EdgeInsets.zero,
        child: SizedBox.expand(key: contentKey),
      ),
    );
    expect(
      tester.getRect(find.byKey(contentKey)),
      const Rect.fromLTRB(40, 36, 360, 728),
    );
  });

  testWidgets('navigation mode changes update the reserve', (tester) async {
    const gestureData = MediaQueryData(
      viewPadding: EdgeInsets.only(bottom: 20),
      systemGestureInsets: EdgeInsets.only(bottom: 24),
    );
    await start(tester, gestureData);
    expect(tester.getRect(find.byKey(contentKey)).bottom, 752);
    await start(
      tester,
      const MediaQueryData(
        padding: EdgeInsets.only(bottom: 48),
        viewPadding: EdgeInsets.only(bottom: 48),
      ),
    );
    expect(tester.getRect(find.byKey(contentKey)).bottom, 728);
  });
}