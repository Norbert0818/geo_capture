import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

typedef SignInCallback =
    Future<void> Function(String username, String password);

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
    this.onSignIn,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final SignInCallback? onSignIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _hidePassword = true;
  bool _isSubmitting = false;
  bool _signInUnavailable = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    final signIn = widget.onSignIn;

    if (signIn == null) {
      setState(() => _signInUnavailable = true);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _signInUnavailable = false;
    });

    try {
      await signIn(_username.text.trim(), _password.text);
    } catch (_) {
      if (mounted) {
        setState(() => _signInUnavailable = true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _clearError(String _) {
    if (_signInUnavailable) {
      setState(() => _signInUnavailable = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.appTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Tooltip(
                        message: t.language,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'en', label: Text('EN')),
                            ButtonSegment(value: 'ro', label: Text('RO')),
                          ],
                          selected: {widget.locale.languageCode},
                          showSelectedIcon: false,
                          onSelectionChanged: _isSubmitting
                              ? null
                              : (values) => widget.onLocaleChanged(
                                  Locale(values.single),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _buildForm(context, t),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);

    return Form(
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
              enabled: !_isSubmitting,
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
              enabled: !_isSubmitting,
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
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) =>
                  value == null || value.isEmpty ? t.passwordRequired : null,
            ),
            const SizedBox(height: 20),
            if (_signInUnavailable)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    t.signInUnavailable,
                    key: const ValueKey('signInError'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            FilledButton.icon(
              key: const ValueKey('signInButton'),
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_isSubmitting ? t.signingIn : t.signIn),
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
    );
  }
}
