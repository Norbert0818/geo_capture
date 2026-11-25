import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/admin/account_credentials_dialog.dart';
import 'package:geo_capture/features/admin/admin_accounts_repository.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import 'accounts_test_support.dart';

void main() {
  for (final language in ['en', 'ro']) {
    testWidgets('$language copies only the exact temporary password', (
        tester,
        ) async {
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
            () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final account = AccountCredentials.fromJson(
        credentialsJson(username: 'nnor'),
      ).account;
      for (final password in [
        'Gc9!GeneratedTestPassword1234',
        'Gc9!Replacement_Test-Password_1234',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: AccountCredentialsDialog(
                key: ValueKey(password),
                credentials: AccountCredentials(account, password),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            language == 'en'
                ? 'Copy temporary password'
                : 'Copiază parola temporară',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('copyTemporaryPassword')));
        await tester.pumpAndSettle();
        expect(copied, password);
        expect(copied, isNot(contains('nnor')));
        expect(copied, isNot(contains('\n')));
      }
    });
  }
}