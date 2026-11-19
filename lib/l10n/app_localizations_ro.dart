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

  @override
  String get invalidCredentials => 'Nume de utilizator sau parolă incorectă.';

  @override
  String get serviceUnavailable =>
      'Serviciul nu este disponibil. Încearcă din nou.';

  @override
  String get tooManyAttempts =>
      'Prea multe încercări. Așteaptă și încearcă din nou.';

  @override
  String get sessionExpired => 'Sesiunea a expirat. Autentifică-te din nou.';

  @override
  String get accessDenied => 'Nu ai permisiunea de a efectua această acțiune.';

  @override
  String get requestExpired => 'Cererea a expirat. Încearcă din nou.';

  @override
  String get invalidInput => 'Verifică informațiile introduse.';

  @override
  String get changePasswordTitle => 'Setează propria parolă';

  @override
  String get changePasswordDescription =>
      'Schimbă parola temporară înainte de a continua.';

  @override
  String get currentPassword => 'Parola actuală';

  @override
  String get newPassword => 'Parola nouă';

  @override
  String get confirmPassword => 'Confirmă parola nouă';

  @override
  String get newPasswordRequired => 'Introdu o parolă nouă.';

  @override
  String get confirmPasswordRequired => 'Confirmă parola nouă.';

  @override
  String get passwordsDoNotMatch => 'Parolele nu coincid.';

  @override
  String get passwordRules =>
      'Folosește minimum 12 caractere, litere mari și mici, o cifră și 4 caractere diferite.';

  @override
  String get passwordUnchanged => 'Alege o parolă diferită de parola actuală.';

  @override
  String get wrongCurrentPassword => 'Parola actuală este incorectă.';

  @override
  String get savePassword => 'Salvează parola';

  @override
  String get savingPassword => 'Se salvează parola...';

  @override
  String get signOut => 'Deconectare';

  @override
  String get signingOut => 'Se deconectează...';

  @override
  String get checkingSession => 'Se verifică sesiunea...';

  @override
  String get retry => 'Încearcă din nou';

  @override
  String get accountTitle => 'Contul tău';

  @override
  String get accountReady => 'Ești autentificat.';

  @override
  String get administrator => 'Administrator';

  @override
  String get userRole => 'Utilizator';
}
