import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/models/session_user.dart';
import '../../core/widgets/auth_shell.dart';
import '../../l10n/app_localizations.dart';
import 'auth_error_message.dart';
import '../capture/capture_page.dart';
import '../capture/photo_draft_store.dart';
import '../uploads/upload_controller.dart';
import '../uploads/upload_repository.dart';
import '../uploads/history_strings.dart';
import '../uploads/upload_history_page.dart';
import '../uploads/upload_history_repository.dart';
import '../admin/admin_uploads_page.dart';
import '../admin/admin_accounts_page.dart';
import '../admin/admin_accounts_repository.dart';
import '../admin/admin_accounts_strings.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.user,
    required this.locale,
    required this.onLocaleChanged,
    required this.onSignOut,
    this.uploadRepository,
    this.historyRepository,
    this.accountsRepository,
  });

  final SessionUser user;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final Future<void> Function() onSignOut;
  final UploadRepository? uploadRepository;
  final UploadHistoryRepository? historyRepository;
  final AdminAccountsRepository? accountsRepository;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _drafts = PhotoDraftStore();
  UploadController? _uploads;

  @override
  void initState() {
    super.initState();
    final repository = widget.uploadRepository;
    if (repository != null) {
      _uploads = UploadController(drafts: _drafts, repository: repository);
    }
  }

  @override
  void dispose() {
    _uploads?.dispose();
    _drafts.dispose();
    super.dispose();
  }

  void _openPhotos() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CapturePage(drafts: _drafts, uploads: _uploads),
      ),
    );
  }

  void _openUploads({bool allUsers = false}) {
    final repository = widget.historyRepository;
    if (repository == null || (allUsers && !widget.user.isAdmin)) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => allUsers
            ? AdminUploadsPage(repository: repository)
            : UploadHistoryPage(repository: repository),
      ),
    );
  }

  bool _busy = false;
  String? _errorCode;

  Future<void> _signOut() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _errorCode = null;
    });

    try {
      await widget.onSignOut();
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorCode = error.code);
    } catch (_) {
      if (mounted) setState(() => _errorCode = 'service_unavailable');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final history = HistoryStrings.of(context);

    return AuthShell(
      locale: widget.locale,
      onLocaleChanged: widget.onLocaleChanged,
      enabled: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            t.accountTitle,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(t.accountReady, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SelectableText(
            widget.user.username,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            widget.user.isAdmin ? t.administrator : t.userRole,
            textAlign: TextAlign.center,
          ),
          if (_errorCode != null) ...[
            const SizedBox(height: 16),
            Text(
              authErrorMessage(t, _errorCode!),
              key: const ValueKey('accountError'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _drafts,
            builder: (context, _) => FilledButton.icon(
              key: const ValueKey('openPhotosButton'),
              onPressed: _busy ? null : _openPhotos,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text('${t.capturePhotos} (${_drafts.items.length})'),
            ),
          ),
          if (widget.historyRepository != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('myUploadsButton'),
              onPressed: _busy ? null : () => _openUploads(),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(history.myUploads),
            ),
            if (widget.user.isAdmin) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('allUploadsButton'),
                onPressed: _busy ? null : () => _openUploads(allUsers: true),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: Text(history.allUploads),
              ),
            ],
          ],
          if (widget.user.isAdmin && widget.accountsRepository != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('manageUsersButton'),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => AdminAccountsPage(
                          repository: widget.accountsRepository!,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.manage_accounts_outlined),
              label: Text(AdminAccountsStrings.of(context).title),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            key: const ValueKey('signOutButton'),
            onPressed: _busy ? null : _signOut,
            child: Text(_busy ? t.signingOut : t.signOut),
          ),
        ],
      ),
    );
  }
}
