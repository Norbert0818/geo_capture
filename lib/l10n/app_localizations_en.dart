// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'GeoCapture';

  @override
  String get signInTitle => 'Welcome back';

  @override
  String get signInDescription =>
      'Sign in to capture and manage your field photos.';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get signIn => 'Sign in';

  @override
  String get signingIn => 'Signing in...';

  @override
  String get usernameRequired => 'Enter your username.';

  @override
  String get passwordRequired => 'Enter your password.';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get adminAccountHint =>
      'Use the account provided by your administrator.';

  @override
  String get signInUnavailable =>
      'Sign-in is currently unavailable. Please try again later.';

  @override
  String get language => 'Language';
}
