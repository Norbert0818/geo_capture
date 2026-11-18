import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/login_page.dart';
import 'l10n/app_localizations.dart';

class GeoCaptureApp extends StatefulWidget {
  const GeoCaptureApp({super.key, this.onSignIn});

  final SignInCallback? onSignIn;

  @override
  State<GeoCaptureApp> createState() => _GeoCaptureAppState();
}

class _GeoCaptureAppState extends State<GeoCaptureApp> {
  Locale _locale = const Locale('en');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: AppTheme.light,
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: LoginPage(
        locale: _locale,
        onLocaleChanged: (locale) => setState(() => _locale = locale),
        onSignIn: widget.onSignIn,
      ),
    );
  }
}
