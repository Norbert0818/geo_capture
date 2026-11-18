// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Romanian Moldavian Moldovan (`ro`).
class AppLocalizationsRo extends AppLocalizations {
  AppLocalizationsRo([String locale = 'ro']) : super(locale);

  @override
  String get appTitle => 'GeoCapture';

  @override
  String get signInTitle => 'Bine ai revenit';

  @override
  String get signInDescription =>
      'Autentifică-te pentru a realiza și gestiona fotografiile din teren.';

  @override
  String get username => 'Nume de utilizator';

  @override
  String get password => 'Parolă';

  @override
  String get signIn => 'Autentificare';

  @override
  String get signingIn => 'Se autentifică...';

  @override
  String get usernameRequired => 'Introdu numele de utilizator.';

  @override
  String get passwordRequired => 'Introdu parola.';

  @override
  String get showPassword => 'Afișează parola';

  @override
  String get hidePassword => 'Ascunde parola';

  @override
  String get adminAccountHint => 'Folosește contul oferit de administrator.';

  @override
  String get signInUnavailable =>
      'Autentificarea nu este disponibilă momentan. Încearcă din nou mai târziu.';

  @override
  String get language => 'Limbă';
}
