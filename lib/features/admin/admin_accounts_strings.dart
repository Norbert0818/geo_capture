import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

class AdminAccountsStrings {
  const AdminAccountsStrings(this.ro);
  factory AdminAccountsStrings.of(BuildContext context) => AdminAccountsStrings(
    Localizations.localeOf(context).languageCode == 'ro',
  );
  final bool ro;
  String _t(String en, String romanian) => ro ? romanian : en;
  String get title => _t('Users', 'Utilizatori');
  String get create => _t('Create user', 'Creează utilizator');
  String get username => _t('Username', 'Nume de utilizator');
  String get active => _t('Active', 'Activ');
  String get disabled => _t('Disabled', 'Dezactivat');
  String get pending => _t(
    'First password change pending',
    'Prima schimbare a parolei este în așteptare',
  );
  String get admin => _t('Administrator', 'Administrator');
  String get user => _t('User', 'Utilizator');
  String get protected => _t(
    'Administrator accounts are protected.',
    'Conturile de administrator sunt protejate.',
  );
  String get disable => _t('Disable', 'Dezactivează');
  String get enable => _t('Enable', 'Activează');
  String get cancel => _t('Cancel', 'Anulează');
  String get refresh => _t('Refresh', 'Reîmprospătează');
  String get retry => _t('Try again', 'Încearcă din nou');
  String get empty => _t('No users found.', 'Nu există utilizatori.');
  String get saving => _t('Saving...', 'Se salvează...');
  String get created => _t('Created at', 'Creat la');
  String get tempPassword => _t('Temporary password', 'Parolă temporară');
  String get newTemp => _t('New temporary password', 'Parolă temporară nouă');
  String get credentials => _t('Account credentials', 'Date de autentificare');
  String get copy => _t('Copy credentials', 'Copiază datele');
  String get copied => _t('Copied', 'Copiat');
  String get done => _t('I saved the credentials', 'Am salvat datele');
  String get secretNotice => _t(
    'Save these credentials now. The password is shown only here. The user must change it on the first sign-in.',
    'Salvează acum aceste date. Parola este afișată doar aici. Utilizatorul trebuie să o schimbe la prima autentificare.',
  );
  String get usernameHint => _t(
    '1–64 characters: A–Z, a–z, 0–9, . _ @ + -',
    '1–64 caractere: A–Z, a–z, 0–9, . _ @ + -',
  );
  String page(int number, int total) =>
      _t('Page $number of $total', 'Pagina $number din $total');
  String date(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());
  String confirmStatus(String name, bool active) => active
      ? _t('Enable $name?', 'Activezi $name?')
      : _t(
          'Disable $name? Existing sessions will stop working.',
          'Dezactivezi $name? Sesiunile existente nu vor mai funcționa.',
        );
  String confirmTemp(String name) => _t(
    'Generate a new temporary password for $name? The previous temporary password will stop working.',
    'Generezi o parolă temporară nouă pentru $name? Parola temporară anterioară nu va mai funcționa.',
  );
  String error(String code) => switch (code) {
    'username_exists' => _t(
      'This username already exists. Refresh the list to find it.',
      'Acest nume de utilizator există deja. Reîmprospătează lista pentru a-l găsi.',
    ),
    'invalid_username' => usernameHint,
    'account_conflict' => _t(
      'This account changed. Refresh the list before trying again.',
      'Contul a fost modificat. Reîmprospătează lista înainte de a reîncerca.',
    ),
    'account_protected' => protected,
    'initial_password_completed' => _t(
      'The user has already changed the initial password.',
      'Utilizatorul a schimbat deja parola inițială.',
    ),
    'forbidden' => _t(
      'Only administrators can manage users.',
      'Doar administratorii pot gestiona utilizatori.',
    ),
    'session_expired' => _t(
      'Your session has expired. Sign in again.',
      'Sesiunea a expirat. Autentifică-te din nou.',
    ),
    'not_found' => _t(
      'The account could not be found.',
      'Contul nu a fost găsit.',
    ),
    _ => _t(
      'The action could not be confirmed. Refresh the user list before trying again.',
      'Acțiunea nu a putut fi confirmată. Reîmprospătează lista de utilizatori înainte de a reîncerca.',
    ),
  };
}
