import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/widgets/auth_shell.dart';
import '../../l10n/app_localizations.dart';
import 'auth_error_message.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
    required this.onChangePassword,
    required this.onSignOut,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final Future<void> Function(String newPassword) onChangePassword;
  final Future<void> Function() onSignOut;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  final _visibleFields = <String>{};

  bool _busy = false;
  bool _signingOut = false;
  String? _errorCode;

  @override
  void dispose() {
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool signingOut = false,
  }) async {
    if (_busy) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _signingOut = signingOut;
      _errorCode = null;
    });

    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorCode = error.code);
    } catch (_) {
      if (mounted) setState(() => _errorCode = 'service_unavailable');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _signingOut = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    await _run(() => widget.onChangePassword(_newPassword.text));
  }

  String? _validateNewPassword(String? value, AppLocalizations t) {
    if (value == null || value.isEmpty) return t.newPasswordRequired;
    if (value.length > 1024) return t.invalidInput;

    if (value.length < 12 ||
        !RegExp(r'[a-z]').hasMatch(value) ||
        !RegExp(r'[A-Z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value) ||
        value.codeUnits.toSet().length < 4) {
      return t.passwordRules;
    }

    return null;
  }

  Widget _passwordField({
    required String name,
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    bool isNew = false,
    bool isLast = false,
  }) {
    final t = AppLocalizations.of(context)!;
    final visible = _visibleFields.contains(name);

    return TextFormField(
      key: ValueKey(name),
      controller: controller,
      enabled: !_busy,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [
        isNew ? AutofillHints.newPassword : AutofillHints.password,
      ],
      textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: isLast ? (_) => _submit() : null,
      onChanged: (_) {
        if (_errorCode != null) setState(() => _errorCode = null);
      },
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: visible ? t.hidePassword : t.showPassword,
          onPressed: _busy
              ? null
              : () => setState(() {
                  if (visible) {
                    _visibleFields.remove(name);
                  } else {
                    _visibleFields.add(name);
                  }
                }),
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
      ),
      validator: validator,
    );
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
                Icons.lock_reset,
                size: 44,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                t.changePasswordTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(t.changePasswordDescription, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              _passwordField(
                name: 'newPasswordField',
                label: t.newPassword,
                controller: _newPassword,
                isNew: true,
                validator: (value) => _validateNewPassword(value, t),
              ),
              const SizedBox(height: 8),
              Text(t.passwordRules, style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              _passwordField(
                name: 'confirmPasswordField',
                label: t.confirmPassword,
                controller: _confirmation,
                isNew: true,
                isLast: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return t.confirmPasswordRequired;
                  }

                  return value == _newPassword.text
                      ? null
                      : t.passwordsDoNotMatch;
                },
              ),
              if (_errorCode != null) ...[
                const SizedBox(height: 16),
                Text(
                  authErrorMessage(t, _errorCode!),
                  key: const ValueKey('passwordChangeError'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('savePasswordButton'),
                onPressed: _busy ? null : _submit,
                child: Text(
                  _busy && !_signingOut ? t.savingPassword : t.savePassword,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('signOutButton'),
                onPressed: _busy
                    ? null
                    : () => _run(widget.onSignOut, signingOut: true),
                child: Text(_signingOut ? t.signingOut : t.signOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
