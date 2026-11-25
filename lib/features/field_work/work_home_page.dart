import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/session_user.dart';
import '../../core/widgets/control_safe_area.dart';
import 'work_editor_page.dart';
import 'work_models.dart';
import 'work_list_filters.dart';
import 'work_list_filter_panel.dart';
import 'work_photo_view.dart';
import 'work_qr_page.dart';
import 'work_repository.dart';
import 'work_storage.dart';
import 'work_strings.dart';

class FieldWorkServices {
  const FieldWorkServices({required this.repository, required this.storage});
  final WorkRepository repository;
  final SembastWorkStorage storage;
}

class WorkHomePage extends StatefulWidget {
  const WorkHomePage({super.key, required this.services, required this.user});
  final FieldWorkServices services;
  final SessionUser user;
  @override
  State<WorkHomePage> createState() => _WorkHomePageState();
}

class _WorkHomePageState extends State<WorkHomePage> {
  late final _store = widget.services.storage.forUser(widget.user.id);
  WorkRepository get _repository => widget.services.repository;
  List<WorkDraft> _drafts = [];
  List<Map<String, dynamic>> _items = [];
  WorkSettings _settings = const WorkSettings(
    allowQrGeneration: false,
    version: '00000000-0000-0000-0000-000000000000',
  );
  bool _loading = true,
      _localReady = false,
      _all = false,
      _settingsBusy = false;
  int _page = 1, _total = 0, _loadId = 0;
  WorkListFilters _filters = const WorkListFilters();
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _current(int id) => mounted && id == _loadId;

  Future<void> _load() async {
    final id = ++_loadId;
    final all = _all, number = _page, filters = _filters;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drafts = await _store.readAll();
      if (!_current(id)) return;
      setState(() {
        _drafts = drafts;
        _localReady = true;
      });
    } catch (_) {
      if (!_current(id)) return;
      setState(() {
        _localReady = false;
        _error = 'work_local_invalid';
      });
    }
    try {
      final settings = await _repository.settings();
      if (!_current(id)) return;
      final repository = _repository;
      if (repository is! FilteredWorkRepository && !filters.isEmpty) {
        throw StateError('work_filters_unavailable');
      }
      final page = repository is FilteredWorkRepository
          ? await repository.listFiltered(
        all: all,
        page: number,
        filters: filters,
      )
          : await repository.list(all: all, page: number);
      if (!_current(id)) return;
      final total = page['total'] as int;
      final lastPage = total == 0 ? 1 : (total + 19) ~/ 20;
      if (number > lastPage) {
        setState(() => _page = lastPage);
        await _load();
        return;
      }
      setState(() {
        _settings = settings;
        _items = (page['items'] as List)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _total = total;
      });
    } catch (failure) {
      if (_current(id) && _error == null) {
        setState(() => _error = failure.toString());
      }
    } finally {
      if (_current(id)) setState(() => _loading = false);
    }
  }

  void _applyFilters(WorkListFilters value) {
    setState(() {
      _filters = _all && widget.user.isAdmin ? value : value.withoutOwner();
      _page = 1;
      _total = 0;
      _items = [];
    });
    _load();
  }

  Future<void> _edit(WorkDraft draft) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkEditorPage(
          draft: draft,
          store: _store,
          repository: _repository,
          allowGeneration: _settings.allowQrGeneration,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _newWork(WorkKind kind) => _edit(
    WorkDraft(
      id: const Uuid().v4(),
      document: WorkDocument(kind: kind),
    ),
  );
  Future<void> _discard(WorkDraft draft) async {
    final s = WorkStrings.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.text('Discard local draft?', 'Ștergi ciorna locală?')),
        content: Text(
          s.text(
            'Unuploaded photos in this draft will be removed. Already uploaded revisions remain on the server. If an upload was interrupted, check the server list first.',
            'Fotografiile neîncărcate din această ciornă vor fi eliminate. Versiunile încărcate rămân pe server. Dacă încărcarea a fost întreruptă, verifică mai întâi lista de pe server.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(s.text('Cancel', 'Anulează')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s.text('Discard', 'Șterge ciorna')),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await _store.remove(draft);
      if (mounted) await _load();
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    }
  }

  Future<void> _open(String id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkDetailsPage(
          id: id,
          repository: _repository,
          onEdit: (details) async {
            final existing = _drafts.where((draft) => draft.id == id);
            await _edit(
              existing.isNotEmpty
                  ? existing.first
                  : WorkDraft(
                id: id,
                document: details.document,
                expectedVersion: details.version,
                reason: '',
              ),
            );
          },
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _toggleGeneration(bool value) async {
    if (_settingsBusy) return;
    setState(() => _settingsBusy = true);
    try {
      final settings = await _repository.updateSettings(_settings, value);
      if (mounted) setState(() => _settings = settings);
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    } finally {
      if (mounted) setState(() => _settingsBusy = false);
    }
  }

  String _serials(Map<String, dynamic> item) {
    final oldSerial = item['oldSerialNumber'] as String?;
    final newSerial = item['newSerialNumber'] as String?;
    if (oldSerial != null && newSerial != null) {
      return '$oldSerial → $newSerial';
    }
    return newSerial ?? oldSerial ?? item['serialNumber'] as String? ?? '—';
  }

  String _places(Map<String, dynamic> item) {
    final locations =
        (item['locations'] as List?)?.cast<String>() ?? const <String>[];
    return locations.isEmpty ? '' : '\n${locations.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ControlSafeArea(
        top: false,
        child: ListView(
          children: [
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(s.error(_error)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                s.text(
                  'Choose work type before taking photos',
                  'Alege tipul lucrării înainte de fotografiere',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final kind in WorkKind.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton.tonalIcon(
                  key: ValueKey('newWork:${kind.name}'),
                  onPressed: _localReady && !_loading
                      ? () => _newWork(kind)
                      : null,
                  icon: Icon(switch (kind) {
                    WorkKind.replacement => Icons.swap_horiz,
                    WorkKind.repair => Icons.build_outlined,
                    WorkKind.removal => Icons.remove_circle_outline,
                    WorkKind.pit => Icons.landscape_outlined,
                  }),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(s.kind(kind)),
                  ),
                ),
              ),
            if (widget.user.isAdmin)
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      key: const ValueKey('allowWorkQrGeneration'),
                      value: _settings.allowQrGeneration,
                      onChanged: _loading || _settingsBusy
                          ? null
                          : _toggleGeneration,
                      title: Text(
                        s.text(
                          'Allow new QR generation',
                          'Permite generarea de QR-uri noi',
                        ),
                      ),
                      subtitle: Text(
                        s.text(
                          'Existing QR scanning stays available.',
                          'Scanarea codurilor existente rămâne disponibilă.',
                        ),
                      ),
                    ),
                    SwitchListTile(
                      key: const ValueKey('showAllWork'),
                      value: _all,
                      onChanged: _loading
                          ? null
                          : (value) {
                        setState(() {
                          _all = value;
                          if (!value) _filters = _filters.withoutOwner();
                          _page = 1;
                          _items = [];
                          _total = 0;
                        });
                        _load();
                      },
                      title: Text(
                        s.text(
                          'Show all users’ work',
                          'Arată lucrările tuturor utilizatorilor',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_drafts.isNotEmpty) ...[
              const Divider(),
              Text(
                s.text(
                  'Local drafts — continue or retry',
                  'Ciorne locale — continuă sau reîncearcă',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final draft in _drafts)
                Card(
                  child: ListTile(
                    title: Text(s.kind(draft.document.kind)),
                    subtitle: Text(
                      '${draft.document.oldPole?.serialNumber ?? ''} → ${draft.document.newPole?.serialNumber ?? ''}\n${draft.document.photos.length} ${s.text('photos', 'fotografii')}',
                    ),
                    isThreeLine: true,
                    onTap: _localReady ? () => _edit(draft) : null,
                    trailing: IconButton(
                      onPressed: () => _discard(draft),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
            ],
            const Divider(),
            Text(
              s.text('Uploaded work', 'Lucrări încărcate'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            WorkListFilterPanel(
              filters: _filters,
              showOwner: widget.user.isAdmin && _all,
              busy: _loading,
              onApply: _applyFilters,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${s.text('Page', 'Pagina')} $_page / ${_total == 0 ? 1 : (_total + 19) ~/ 20} · $_total ${s.text('results', 'rezultate')}',
                key: const ValueKey('workResultCount'),
              ),
            ),
            for (final item in _items)
              Card(
                child: ListTile(
                  onTap: () => _open(item['id'] as String),
                  title: Text(
                    '${s.kind(WorkKind.values.byName(item['kind'] as String))} · ${_serials(item)}',
                  ),
                  subtitle: Text(
                    '${item['owner']} · v${item['revision']} · ${item['photoCount']} ${s.text('photos', 'fotografii')}${_places(item)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            if (!_loading && _items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  s.text(
                    _filters.isEmpty
                        ? 'No uploaded work yet.'
                        : 'No work matches these filters.',
                    _filters.isEmpty
                        ? 'Nu există încă lucrări încărcate.'
                        : 'Nicio lucrare nu corespunde filtrelor.',
                  ),
                ),
              ),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  key: const ValueKey('previousWorkPage'),
                  onPressed: !_loading && _page > 1
                      ? () {
                    setState(() => _page--);
                    _load();
                  }
                      : null,
                  child: Text(s.text('Previous', 'Înapoi')),
                ),
                TextButton(
                  key: const ValueKey('nextWorkPage'),
                  onPressed: !_loading && _page * 20 < _total
                      ? () {
                    setState(() => _page++);
                    _load();
                  }
                      : null,
                  child: Text(s.text('Next', 'Înainte')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WorkDetailsPage extends StatefulWidget {
  const WorkDetailsPage({
    super.key,
    required this.id,
    required this.repository,
    required this.onEdit,
  });
  final String id;
  final WorkRepository repository;
  final Future<void> Function(WorkDetails) onEdit;
  @override
  State<WorkDetailsPage> createState() => _WorkDetailsPageState();
}

class _WorkDetailsPageState extends State<WorkDetailsPage> {
  late Future<WorkDetails> _details = widget.repository.details(widget.id);
  Future<void> _history() async {
    final s = WorkStrings.of(context);
    try {
      final items = await widget.repository.history(widget.id);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(s.text('Change history', 'Istoricul modificărilor')),
            ),
            body: ControlSafeArea(
              top: false,
              child: ListView(
                children: [
                  for (final item in items)
                    Card(
                      child: ExpansionTile(
                        title: Text('v${item['revision']} · ${item['actor']}'),
                        subtitle: Text(
                          '${DateTime.parse(item['atUtc'] as String).toLocal()}\n${item['reason']}',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  (item['changes'] as List)
                                      .map((value) => s.change(value as String))
                                      .join(', '),
                                ),
                                _document(
                                  WorkDocument.fromJson(
                                    Map<String, dynamic>.from(
                                      item['document'] as Map,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.error(failure.toString()))));
      }
    }
  }

  Widget _document(WorkDocument doc) {
    final s = WorkStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.kind(doc.kind), style: Theme.of(context).textTheme.titleLarge),
        if (doc.oldPole != null)
          SelectableText(
            '${s.text('Existing / old', 'Existent / vechi')}: ${doc.oldPole!.serialNumber}\nNTET: ${doc.oldPole!.ntetCode}',
          ),
        if (doc.newPole != null) ...[
          SelectableText(
            '${s.text('New', 'Nou')}: ${doc.newPole!.serialNumber}\nNTET: ${doc.newPole!.ntetCode}',
          ),
          WorkQrCard(pole: doc.newPole!),
        ],
        if (doc.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(doc.notes),
          ),
        for (final photo in doc.photos)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Text(s.role(photo.role)),
                  InkWell(
                    onTap: () => showWorkPhoto(
                      context,
                      photo,
                      widget.id,
                      widget.repository,
                    ),
                    child: WorkPhotoImage(
                      photo: photo,
                      workId: widget.id,
                      repository: widget.repository,
                    ),
                  ),
                  SelectableText(photo.overlayText),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('Work details', 'Detalii lucrare')),
        actions: [
          IconButton(onPressed: _history, icon: const Icon(Icons.history)),
        ],
      ),
      body: ControlSafeArea(
        top: false,
        child: FutureBuilder<WorkDetails>(
          future: _details,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(
                        () => _details = widget.repository.details(widget.id),
                  ),
                  child: Text(s.text('Retry', 'Reîncearcă')),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final work = snapshot.data!;
            return ListView(
              children: [
                Text('${work.owner} · v${work.revision}'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('editUploadedWork'),
                  onPressed: () async {
                    await widget.onEdit(work);
                    if (mounted) {
                      setState(
                            () => _details = widget.repository.details(widget.id),
                      );
                    }
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(
                    s.text(
                      'Edit — create a new revision',
                      'Modifică — creează o versiune nouă',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _document(work.document),
              ],
            );
          },
        ),
      ),
    );
  }
}