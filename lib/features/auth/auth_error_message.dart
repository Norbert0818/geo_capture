import '../../l10n/app_localizations.dart';

String authErrorMessage(AppLocalizations t, String code) {
  return switch (code) {
    'invalid_credentials' => t.invalidCredentials,
    'too_many_attempts' => t.tooManyAttempts,
    'session_expired' => t.sessionExpired,
    'forbidden' => t.accessDenied,
    'csrf_invalid' => t.requestExpired,
    'invalid_input' => t.invalidInput,
    'password_unchanged' => t.passwordUnchanged,
    'wrong_current_password' => t.wrongCurrentPassword,
    'password_rules' => t.passwordRules,
    _ => t.serviceUnavailable,
  };
}
