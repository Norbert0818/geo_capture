import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/app.dart';

Finder byName(String name) => find.byKey(ValueKey(name));

Future<void> fillCredentials(
  WidgetTester tester, {
  String username = 'worker01',
  String password = 'example-password',
}) async {
  await tester.enterText(byName('usernameField'), username);
  await tester.enterText(byName('passwordField'), password);
}

Future<void> pressSignIn(WidgetTester tester) async {
  await tester.ensureVisible(byName('signInButton'));
  await tester.tap(byName('signInButton'));
}

void main() {
  testWidgets('starts in English', (tester) async {
    await tester.pumpWidget(const GeoCaptureApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('switches to Romanian without losing input', (tester) async {
    await tester.pumpWidget(const GeoCaptureApp());
    await tester.pumpAndSettle();
    await fillCredentials(tester);

    await tester.ensureVisible(find.text('RO'));
    await tester.tap(find.text('RO'));
    await tester.pumpAndSettle();

    expect(find.text('Bine ai revenit'), findsOneWidget);
    expect(find.text('Nume de utilizator'), findsOneWidget);
    expect(find.text('Parolă'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(byName('usernameField')).controller!.text,
      'worker01',
    );
    expect(
      tester.widget<TextFormField>(byName('passwordField')).controller!.text,
      'example-password',
    );
  });

  testWidgets('rejects empty fields without submitting', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      GeoCaptureApp(
        onSignIn: (username, password) async {
          calls++;
        },
      ),
    );
    await tester.pumpAndSettle();

    await pressSignIn(tester);
    await tester.pumpAndSettle();

    expect(find.text('Enter your username.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('can reveal and hide the password', (tester) async {
    await tester.pumpWidget(const GeoCaptureApp());
    await tester.pumpAndSettle();

    final passwordInput = find.descendant(
      of: byName('passwordField'),
      matching: find.byType(TextField),
    );

    expect(tester.widget<TextField>(passwordInput).obscureText, isTrue);

    await tester.ensureVisible(byName('passwordVisibilityButton'));
    await tester.tap(byName('passwordVisibilityButton'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(passwordInput).obscureText, isFalse);

    await tester.tap(byName('passwordVisibilityButton'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(passwordInput).obscureText, isTrue);
  });

  testWidgets('submits once and preserves password whitespace', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    String? receivedUsername;
    String? receivedPassword;

    await tester.pumpWidget(
      GeoCaptureApp(
        onSignIn: (username, password) {
          calls++;
          receivedUsername = username;
          receivedPassword = password;
          return pending.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await fillCredentials(
      tester,
      username: '  worker01  ',
      password: ' secret ',
    );

    await pressSignIn(tester);
    await tester.pump();

    expect(calls, 1);
    expect(receivedUsername, 'worker01');
    expect(receivedPassword, ' secret ');
    expect(
      tester.widget<FilledButton>(byName('signInButton')).onPressed,
      isNull,
    );

    pending.complete();
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(byName('signInButton')).onPressed,
      isNotNull,
    );
  });

  testWidgets('shows an error when sign-in is unavailable', (tester) async {
    await tester.pumpWidget(const GeoCaptureApp());
    await tester.pumpAndSettle();
    await fillCredentials(tester);

    await pressSignIn(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Sign-in is currently unavailable. Please try again later.'),
      findsOneWidget,
    );
  });

  testWidgets('handles a failed sign-in request', (tester) async {
    await tester.pumpWidget(
      GeoCaptureApp(
        onSignIn: (username, password) async {
          throw Exception('Unavailable');
        },
      ),
    );
    await tester.pumpAndSettle();
    await fillCredentials(tester);

    await pressSignIn(tester);
    await tester.pumpAndSettle();

    expect(byName('signInError'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a narrow screen in Romanian', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const GeoCaptureApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('RO'));
    await tester.pumpAndSettle();

    await pressSignIn(tester);
    await tester.pumpAndSettle();

    expect(find.text('Introdu numele de utilizator.'), findsOneWidget);
    expect(find.text('Introdu parola.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
