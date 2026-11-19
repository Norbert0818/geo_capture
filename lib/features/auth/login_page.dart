import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/widgets/auth_shell.dart';
import '../../l10n/app_localizations.dart';
import 'auth_error_message.dart';

typedef SignInCallback =
    Future<void> Function(String username, String password);

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
    required this.onSignIn,
    this.initialErrorCode,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final SignInCallback onSignIn;
  final String? initialErrorCode;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _hidePassword = true;
  bool _busy = false;
  late String? _errorCode = widget.initialErrorCode;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _errorCode = null;
    });

    try {
      await widget.onSignIn(_username.text.trim(), _password.text);
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorCode = error.code);
    } catch (_) {
      if (mounted) setState(() => _errorCode = 'service_unavailable');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearError(String _) {
    if (_errorCode != null) setState(() => _errorCode = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AuthShell(
      locale: widget.locale,
      onLocaleChanged: widget.onLocaleChanged,
      enabled: !_busy,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.photo_camera_outlined,
                size: 44,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                t.signInTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(t.signInDescription, textAlign: TextAlign.center),
              const SizedBox(height: 28),
              TextFormField(
                key: const ValueKey('usernameField'),
                controller: _username,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                onChanged: _clearError,
                decoration: InputDecoration(
                  labelText: t.username,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? t.usernameRequired
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('passwordField'),
                controller: _password,
                enabled: !_busy,
                obscureText: _hidePassword,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onChanged: _clearError,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: t.password,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    key: const ValueKey('passwordVisibilityButton'),
                    tooltip: _hidePassword ? t.showPassword : t.hidePassword,
                    onPressed: _busy
                        ? null
                        : () => setState(() => _hidePassword = !_hidePassword),
                    icon: Icon(
                      _hidePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? t.passwordRequired : null,
              ),
              if (_errorCode != null) ...[
                const SizedBox(height: 16),
                Text(
                  authErrorMessage(t, _errorCode!),
                  key: const ValueKey('signInError'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('signInButton'),
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? t.signingIn : t.signIn),
              ),
              const SizedBox(height: 16),
              Text(
                t.adminAccountHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
