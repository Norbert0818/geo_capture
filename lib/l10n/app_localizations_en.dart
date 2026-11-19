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
  String get signInDescription => 'Sign in to capture and manage your field photos.';

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
  String get adminAccountHint => 'Use the account provided by your administrator.';

  @override
  String get signInUnavailable => 'Sign-in is currently unavailable. Please try again later.';

  @override
  String get language => 'Language';

  @override
  String get invalidCredentials => 'Incorrect username or password.';

  @override
  String get serviceUnavailable => 'The service is unavailable. Please try again.';

  @override
  String get tooManyAttempts => 'Too many attempts. Please wait and try again.';

  @override
  String get sessionExpired => 'Your session has expired. Please sign in again.';

  @override
  String get accessDenied => 'You do not have permission to perform this action.';

  @override
  String get requestExpired => 'The request has expired. Please try again.';

  @override
  String get invalidInput => 'Please check the entered information.';

  @override
  String get changePasswordTitle => 'Set your own password';

  @override
  String get changePasswordDescription => 'Change your temporary password before continuing.';

  @override
  String get currentPassword => 'Current password';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmPassword => 'Confirm new password';

  @override
  String get newPasswordRequired => 'Enter a new password.';

  @override
  String get confirmPasswordRequired => 'Confirm your new password.';

  @override
  String get passwordsDoNotMatch => 'The passwords do not match.';

  @override
  String get passwordRules => 'Use at least 12 characters, uppercase and lowercase letters, a number, and 4 different characters.';

  @override
  String get passwordUnchanged => 'Choose a password different from your current password.';

  @override
  String get wrongCurrentPassword => 'The current password is incorrect.';

  @override
  String get savePassword => 'Save password';

  @override
  String get savingPassword => 'Saving password...';

  @override
  String get signOut => 'Sign out';

  @override
  String get signingOut => 'Signing out...';

  @override
  String get checkingSession => 'Checking your session...';

  @override
  String get retry => 'Try again';

  @override
  String get accountTitle => 'Your account';

  @override
  String get accountReady => 'You are signed in.';

  @override
  String get administrator => 'Administrator';

  @override
  String get userRole => 'User';

  @override
  String get capturePhotos => 'Photos';

  @override
  String get captureTitle => 'Capture photos';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get takingPhoto => 'Getting location and taking photo...';

  @override
  String get cameraStarting => 'Starting camera...';

  @override
  String get cameraUnavailable => 'No camera is available. Check that another app is not using it.';

  @override
  String get cameraPermissionDenied => 'Allow camera access in your device or browser settings.';

  @override
  String get locationPermissionDenied => 'Allow location access to attach coordinates to your photos.';

  @override
  String get locationServicesDisabled => 'Turn on location services and try again.';

  @override
  String get locationTimeout => 'Location could not be determined in time. Try again.';

  @override
  String get locationUnavailable => 'A recent location is unavailable. Check location access and try again.';

  @override
  String get captureFailed => 'The photo could not be taken. Please try again.';

  @override
  String get pendingPhotos => 'Pending photos';

  @override
  String get noPhotosYet => 'No photos yet.';

  @override
  String get removePhoto => 'Remove photo';

  @override
  String get capturedAt => 'Captured at';

  @override
  String get locationMeasuredAt => 'Location measured at';

  @override
  String get locationAccuracy => 'Location accuracy';

  @override
  String get draftNotice => 'Unuploaded photos are cleared when you close or reload the app.';
}
