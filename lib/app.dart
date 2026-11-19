import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/models/session_user.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/auth_shell.dart';
import 'features/auth/account_page.dart';
import 'features/auth/auth_error_message.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/change_password_page.dart';
import 'features/auth/login_page.dart';
import 'l10n/app_localizations.dart';

class GeoCaptureApp extends StatefulWidget {
  const GeoCaptureApp({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<GeoCaptureApp> createState() => _GeoCaptureAppState();
}

class _GeoCaptureAppState extends State<GeoCaptureApp> {
  Locale _locale = const Locale('en');
  SessionUser? _user;
  bool _loading = true;
  String? _startupError;
  String? _loginNotice;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    widget.authRepository.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    setState(() {
      _loading = true;
      _startupError = null;
    });

    SessionUser? user;
    String? error;

    try {
      user = await widget.authRepository.restoreSession();
    } on ApiException catch (failure) {
      error = failure.code;
    } catch (_) {
      error = 'service_unavailable';
    }

    if (!mounted) return;

    setState(() {
      _user = user;
      _startupError = error;
      _loading = false;
    });
  }

  Future<void> _signIn(String username, String password) async {
    final user = await widget.authRepository.signIn(username, password);

    if (!mounted) return;

    setState(() {
      _user = user;
      _loginNotice = null;
    });
  }

  Future<void> _changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      final user = await widget.authRepository.changePassword(
        currentPassword,
        newPassword,
      );

      if (mounted) setState(() => _user = user);
    } on ApiException catch (error) {
      if (error.code == 'session_expired' && mounted) {
        setState(() {
          _user = null;
          _loginNotice = 'session_expired';
        });
      }

      rethrow;
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.authRepository.signOut();
    } on ApiException catch (error) {
      if (error.code != 'session_expired') rethrow;
    }

    if (!mounted) return;

    setState(() {
      _user = null;
      _loginNotice = null;
    });
  }

  void _changeLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  Widget _buildPage(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(t.checkingSession),
            ],
          ),
        ),
      );
    }

    if (_startupError != null) {
      return AuthShell(
        locale: _locale,
        onLocaleChanged: _changeLocale,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              authErrorMessage(t, _startupError!),
              key: const ValueKey('startupError'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('retrySessionButton'),
              onPressed: _restoreSession,
              child: Text(t.retry),
            ),
          ],
        ),
      );
    }

    final user = _user;

    if (user == null) {
      return LoginPage(
        locale: _locale,
        onLocaleChanged: _changeLocale,
        onSignIn: _signIn,
        initialErrorCode: _loginNotice,
      );
    }

    if (user.mustChangePassword) {
      return ChangePasswordPage(
        key: const ValueKey('changePasswordPage'),
        locale: _locale,
        onLocaleChanged: _changeLocale,
        onChangePassword: _changePassword,
        onSignOut: _signOut,
      );
    }

    return AccountPage(
      key: const ValueKey('accountPage'),
      user: user,
      locale: _locale,
      onLocaleChanged: _changeLocale,
      onSignOut: _signOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: AppTheme.light,
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: _buildPage),
    );
  }
}
