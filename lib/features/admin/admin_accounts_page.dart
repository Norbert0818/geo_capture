import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import 'account_credentials_dialog.dart';
import 'admin_accounts_repository.dart';
import 'admin_accounts_strings.dart';

class AdminAccountsPage extends StatefulWidget {
  const AdminAccountsPage({super.key, required this.repository});
  final AdminAccountsRepository repository;
  @override
  State<AdminAccountsPage> createState() => _AdminAccountsPageState();
}

class _AdminAccountsPageState extends State<AdminAccountsPage> {
  AdminAccountsResult? _data;
  String? _loadError, _actionError;
  bool _loading = true, _busy = false;
  int _page = 1, _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int page) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadError = null;
      _actionError = null;
      _page = page;
    });
    try {
      final data = await widget.repository.list(page: page);
      if (mounted && generation == _generation) setState(() => _data = data);
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _loadError = error.code);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _loadError = 'service_unavailable');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _credentials(AccountCredentials credentials) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AccountCredentialsDialog(credentials: credentials),
  );

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final credentials = await showDialog<AccountCredentials>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CreateAccountDialog(repository: widget.repository),
      );
      if (!mounted || credentials == null) return;
      await _credentials(credentials);
      if (mounted) await _load(1);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(
    AdminAccount account, {
    bool temporaryPassword = false,
  }) async {
    if (_busy || account.isAdmin) return;
    final t = AdminAccountsStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          temporaryPassword
              ? t.newTemp
              : account.isActive
              ? t.disable
              : t.enable,
        ),
        content: Text(
          temporaryPassword
              ? t.confirmTemp(account.username)
              : t.confirmStatus(account.username, !account.isActive),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            key: const ValueKey('confirmAccountAction'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              temporaryPassword
                  ? t.newTemp
                  : account.isActive
                  ? t.disable
                  : t.enable,
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      if (temporaryPassword) {
        final credentials = await widget.repository.newTemporaryPassword(
          account,
        );
        if (mounted) await _credentials(credentials);
      } else {
        await widget.repository.setActive(account, !account.isActive);
      }
      if (mounted) await _load(_page);
    } on ApiException catch (error) {
      if (mounted) setState(() => _actionError = error.code);
    } catch (_) {
      if (mounted) setState(() => _actionError = 'service_unavailable');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AdminAccountsStrings.of(context), data = _data;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.title),
          actions: [
            IconButton(
              key: const ValueKey('refreshAccountsButton'),
              tooltip: t.refresh,
              onPressed: _busy || _loading ? null : () => _load(_page),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('createUserButton'),
                        onPressed: _busy || _loading ? null : _create,
                        icon: const Icon(Icons.person_add_outlined),
                        label: Text(t.create),
                      ),
                    ),
                  ),
                  if (_actionError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        t.error(_actionError!),
                        key: const ValueKey('accountActionError'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _loadError != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    t.error(_loadError!),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: () => _load(_page),
                                    child: Text(t.retry),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : data == null || data.items.isEmpty
                        ? Center(child: Text(t.empty))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: data.items.length,
                            itemBuilder: (context, index) {
                              final account = data.items[index];
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        account.username,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          Chip(
                                            label: Text(
                                              account.isActive
                                                  ? t.active
                                                  : t.disabled,
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              account.isAdmin
                                                  ? t.admin
                                                  : t.user,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${t.created}: ${t.date(account.createdAtUtc)}',
                                      ),
                                      if (account.mustChangePassword)
                                        Text(t.pending),
                                      const SizedBox(height: 12),
                                      if (account.isAdmin)
                                        Text(t.protected)
                                      else
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton(
                                              key: ValueKey(
                                                'status:${account.id}',
                                              ),
                                              onPressed: _busy
                                                  ? null
                                                  : () => _change(account),
                                              child: Text(
                                                account.isActive
                                                    ? t.disable
                                                    : t.enable,
                                              ),
                                            ),
                                            if (account.mustChangePassword)
                                              TextButton(
                                                key: ValueKey(
                                                  'temporary:${account.id}',
                                                ),
                                                onPressed: _busy
                                                    ? null
                                                    : () => _change(
                                                        account,
                                                        temporaryPassword: true,
                                                      ),
                                                child: Text(t.newTemp),
                                              ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  if (!_loading && _loadError == null && data != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          IconButton(
                            key: const ValueKey('previousAccountsPage'),
                            onPressed: !_busy && data.hasPrevious
                                ? () => _load(data.page - 1)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              t.page(data.page, data.pages),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('nextAccountsPage'),
                            onPressed: !_busy && data.hasNext
                                ? () => _load(data.page + 1)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
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
}

class _CreateAccountDialog extends StatefulWidget {
  const _CreateAccountDialog({required this.repository});
  final AdminAccountsRepository repository;
  @override
  State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final _form = GlobalKey<FormState>(), _username = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.create(_username.text.trim());
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.code);
    } catch (_) {
      if (mounted) setState(() => _error = 'service_unavailable');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AdminAccountsStrings.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(t.create),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    key: const ValueKey('newUsernameField'),
                    controller: _username,
                    enabled: !_busy,
                    autofocus: true,
                    maxLength: 64,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: t.username,
                      helperText: t.usernameHint,
                      helperMaxLines: 3,
                    ),
                    validator: (value) =>
                        RegExp(
                          r'^[A-Za-z0-9._@+\-]{1,64}$',
                        ).hasMatch((value ?? '').trim())
                        ? null
                        : t.error('invalid_username'),
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null)
                    Text(
                      t.error(_error!),
                      key: const ValueKey('createAccountError'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancelCreateAccount'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
          FilledButton(
            key: const ValueKey('confirmCreateAccount'),
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? t.saving : t.create),
          ),
        ],
      ),
    );
  }
}
