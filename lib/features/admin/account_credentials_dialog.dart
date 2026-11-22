import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_accounts_repository.dart';
import 'admin_accounts_strings.dart';

class AccountCredentialsDialog extends StatefulWidget {
  const AccountCredentialsDialog({super.key, required this.credentials});
  final AccountCredentials credentials;

  @override
  State<AccountCredentialsDialog> createState() =>
      _AccountCredentialsDialogState();
}

class _AccountCredentialsDialogState extends State<AccountCredentialsDialog> {
  bool _copied = false;
  Future<void> _copy() async {
    final t = AdminAccountsStrings.of(context);
    try {
      await Clipboard.setData(
        ClipboardData(
          text:
              '${t.username}: ${widget.credentials.account.username}\n'
              '${t.tempPassword}: ${widget.credentials.temporaryPassword}',
        ),
      );
      if (mounted) setState(() => _copied = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.error('copy_failed'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AdminAccountsStrings.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(t.credentials),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.secretNotice),
                const SizedBox(height: 20),
                Text(t.username),
                SelectableText(
                  widget.credentials.account.username,
                  key: const ValueKey('createdUsername'),
                ),
                const SizedBox(height: 16),
                Text(t.tempPassword),
                SelectableText(
                  widget.credentials.temporaryPassword,
                  key: const ValueKey('createdPassword'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.copy),
            label: Text(_copied ? t.copied : t.copy),
          ),
          FilledButton(
            key: const ValueKey('closeCredentialsButton'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.done),
          ),
        ],
      ),
    );
  }
}
