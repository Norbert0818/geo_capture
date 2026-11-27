import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/control_safe_area.dart';
import 'romania_place_picker.dart';
import 'romania_places.dart';
import 'work_file_share.dart';
import 'work_list_filters.dart';
import 'work_models.dart';
import 'work_repository.dart';
import 'work_strings.dart';

String workStatusLabel(WorkStrings s, String? value) => switch (value) {
  'in_progress' => s.text('In progress', 'În lucru'),
  'repaired' => s.text('Repaired', 'Remediat'),
  'replaced' => s.text('Replaced', 'Înlocuit'),
  'removed' => s.text('Removed', 'Desființat'),
  'pit' => s.text('Pit', 'Groapă'),
  _ => '—',
};

class WorkReportsPage extends StatefulWidget {
  const WorkReportsPage({
    super.key,
    required this.repository,
    required this.onOpen,
    this.shareFile,
    this.loadPlaces,
  });
  final WorkRepository repository;
  final Future<void> Function(String id) onOpen;
  final WorkFileShare? shareFile;
  final Future<RomaniaPlaces> Function()? loadPlaces;
  @override
  State<WorkReportsPage> createState() => _WorkReportsPageState();
}

class _WorkReportsPageState extends State<WorkReportsPage> {
  WorkListFilters _filters = const WorkListFilters(
    kind: WorkKind.repair,
    state: 'completed',
  );
  final _serial = TextEditingController(), _owner = TextEditingController();
  RomaniaPlaces? _places;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true, _exporting = false;
  int _page = 1, _total = 0, _generation = 0;
  String? _error;
  CancelToken? _export;
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final places = await (widget.loadPlaces ?? RomaniaPlaces.load)();
      if (!mounted) return;
      setState(() => _places = places);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _export?.cancel();
    _serial.dispose();
    _owner.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = widget.repository;
      if (repository is! FilteredWorkRepository) {
        throw StateError('work_filters_unavailable');
      }
      final data = await repository.listFiltered(
        all: true,
        page: _page,
        filters: _filters,
      );
      if (!mounted || id != _generation) return;
      final total = data['total'] as int;
      final last = total == 0 ? 1 : (total + 19) ~/ 20;
      if (_page > last) {
        setState(() => _page = last);
        await _load();
        return;
      }
      setState(() {
        _items = (data['items'] as List)
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        _total = total;
      });
    } catch (error) {
      if (mounted && id == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && id == _generation) setState(() => _loading = false);
    }
  }

  void _change(WorkListFilters filters) {
    _export?.cancel();
    setState(() {
      _filters = filters;
      _page = 1;
      _items = [];
      _total = 0;
    });
    _load();
  }

  Future<void> _choosePlace() async {
    final place = await pickRomaniaPlace(
      context,
      _places!,
      initial: _places!.place(_filters.localityCode),
      initialCountyCode: _filters.countyCode.isEmpty
          ? null
          : _filters.countyCode,
    );
    if (place != null && mounted) {
      _change(
        _filters.copyWith(
          countyCode: place.countyCode,
          county: place.county,
          localityCode: place.code ?? '',
          locality: place.name,
        ),
      );
    }
  }

  Future<void> _exportCsv(BuildContext anchor) async {
    final repository = widget.repository;
    if (_exporting || repository is! WorkReportRepository) return;
    final cancellation = CancelToken();
    _export = cancellation;
    final filters = _filters;
    setState(() => _exporting = true);
    try {
      final bytes = await (repository as WorkReportRepository).exportReport(
        filters: filters,
        romanian: Localizations.localeOf(context).languageCode == 'ro',
        cancelToken: cancellation,
      );
      if (!mounted || !anchor.mounted || cancellation.isCancelled) return;
      await (widget.shareFile ?? shareWorkFile)(
        anchor,
        bytes,
        '${filters.kind!.name}_report_${WorkListFilters.date(DateTime.now())}.csv',
        'text/csv',
      );
    } catch (error) {
      if (mounted && !cancellation.isCancelled) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (identical(_export, cancellation)) _export = null;
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _open(String id) async {
    await widget.onOpen(id);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.text('Work reports', 'Rapoarte lucrări'))),
      body: ControlSafeArea(
        top: false,
        child: ListView(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in WorkKind.values)
                  ChoiceChip(
                    key: ValueKey('reportKind:${kind.name}'),
                    label: Text(s.kind(kind)),
                    selected: _filters.kind == kind,
                    onSelected: _loading
                        ? null
                        : (_) => _change(_filters.copyWith(kind: kind)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_places != null)
              DropdownButtonFormField<String>(
                key: ValueKey('reportCounty:${_filters.countyCode}'),
                initialValue: _filters.countyCode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: s.text('County', 'Județ'),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(s.text('All counties', 'Toate județele')),
                  ),
                  for (final county in _places!.counties)
                    DropdownMenuItem(
                      value: county.code,
                      child: Text(county.name),
                    ),
                ],
                onChanged: _loading
                    ? null
                    : (code) => _change(
                  _filters.copyWith(
                    countyCode: code ?? '',
                    county: _places!.county(code)?.name ?? '',
                    locality: '',
                    localityCode: '',
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('reportLocality'),
                  onPressed: _loading || _places == null ? null : _choosePlace,
                  icon: const Icon(Icons.location_city),
                  label: Text(
                    _filters.locality.isEmpty
                        ? s.text(
                      'Choose town / village',
                      'Alege orașul / satul',
                    )
                        : _places?.place(_filters.localityCode)?.label ??
                        _filters.locality,
                  ),
                ),
                if (_filters.locality.isNotEmpty)
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => _change(
                      _filters.copyWith(locality: '', localityCode: ''),
                    ),
                    child: Text(
                      s.text(
                        'All localities in county',
                        'Toate localitățile din județ',
                      ),
                    ),
                  ),
              ],
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('reportState:${_filters.state}'),
              initialValue: _filters.state,
              decoration: InputDecoration(
                labelText: s.text('Work status', 'Starea lucrării'),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(s.text('All statuses', 'Toate stările')),
                ),
                DropdownMenuItem(
                  value: 'completed',
                  child: Text(s.text('Completed', 'Finalizat')),
                ),
                DropdownMenuItem(
                  value: 'in_progress',
                  child: Text(s.text('In progress', 'În lucru')),
                ),
              ],
              onChanged: _loading
                  ? null
                  : (value) => _change(_filters.copyWith(state: value ?? '')),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('reportSerial'),
              controller: _serial,
              decoration: InputDecoration(
                labelText: s.text('Old or new S/N', 'S/N vechi sau nou'),
              ),
              onSubmitted: (_) => _change(
                _filters.copyWith(
                  serial: _serial.text.trim(),
                  owner: _owner.text.trim(),
                ),
              ),
            ),
            TextField(
              key: const ValueKey('reportOwner'),
              controller: _owner,
              decoration: InputDecoration(
                labelText: s.text('Username', 'Utilizator'),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('applyReportFilters'),
                  onPressed: _loading
                      ? null
                      : () => _change(
                    _filters.copyWith(
                      serial: _serial.text.trim(),
                      owner: _owner.text.trim(),
                    ),
                  ),
                  child: Text(s.text('Apply search', 'Aplică căutarea')),
                ),
                Builder(
                  builder: (anchor) => OutlinedButton.icon(
                    key: const ValueKey('exportReportCsv'),
                    onPressed:
                    _loading ||
                        _exporting ||
                        widget.repository is! WorkReportRepository
                        ? null
                        : () => _exportCsv(anchor),
                    icon: const Icon(Icons.download),
                    label: Text(
                      s.text('Export this report', 'Exportă acest raport'),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 28,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _loading
                      ? s.text('Loading…', 'Se încarcă…')
                      : '${s.text('Results', 'Rezultate')}: $_total · ${s.text('Page', 'Pagina')} $_page',
                ),
              ),
            ),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(s.error(_error)),
                      TextButton(
                        onPressed: _places == null ? _start : _load,
                        child: Text(s.text('Retry', 'Reîncearcă')),
                      ),
                    ],
                  ),
                ),
              ),
            WorkReportTable(items: _items, kind: _filters.kind!, onOpen: _open),
            if (!_loading && _items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  s.text(
                    'No work matches the filters.',
                    'Nicio lucrare nu corespunde filtrelor.',
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _loading || _page <= 1
                      ? null
                      : () {
                    _page--;
                    _load();
                  },
                  child: Text(s.text('Previous', 'Înapoi')),
                ),
                TextButton(
                  onPressed: _loading || _page * 20 >= _total
                      ? null
                      : () {
                    _page++;
                    _load();
                  },
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

class WorkReportTable extends StatelessWidget {
  const WorkReportTable({
    super.key,
    required this.items,
    required this.kind,
    required this.onOpen,
  });
  final List<Map<String, dynamic>> items;
  final WorkKind kind;
  final Future<void> Function(String id) onOpen;
  String _number(dynamic value) =>
      value is num ? value.toDouble().toStringAsFixed(6) : '—';
  String _serial(
      Map<String, dynamic> item,
      Map<String, dynamic> report,
      bool isNew,
      WorkStrings s,
      ) {
    final value =
    item[isNew ? 'newSerialNumber' : 'oldSerialNumber'] as String?;
    if (value?.isNotEmpty == true) {
      return report[isNew ? 'newSerialState' : 'oldSerialState'] == 'damaged'
          ? '$value · ${s.text('Damaged label', 'Etichetă deteriorată')}'
          : value!;
    }
    return switch (report[isNew ? 'newSerialState' : 'oldSerialState']) {
      'missing' => s.text('No serial', 'Fără serie'),
      'damaged' => s.text('Damaged label', 'Etichetă deteriorată'),
      _ => '—',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context),
        replacement = kind == WorkKind.replacement;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        dataRowMinHeight: 64,
        dataRowMaxHeight: 112,
        columns: [
          if (replacement) ...[
            DataColumn(
              label: Text(s.text('Old latitude (X)', 'Coordonata X vechi')),
            ),
            DataColumn(
              label: Text(s.text('Old longitude (Y)', 'Coordonata Y vechi')),
            ),
            DataColumn(
              label: Text(s.text('New latitude (X)', 'Coordonata X nou')),
            ),
            DataColumn(
              label: Text(s.text('New longitude (Y)', 'Coordonata Y nou')),
            ),
            DataColumn(label: Text(s.text('Old S/N', 'S/N vechi'))),
            DataColumn(label: Text(s.text('New S/N', 'S/N nou'))),
          ] else ...[
            DataColumn(label: Text(s.text('Latitude (X)', 'Coordonata X'))),
            DataColumn(label: Text(s.text('Longitude (Y)', 'Coordonata Y'))),
            const DataColumn(label: Text('S/N')),
          ],
          DataColumn(label: Text(s.text('Status', 'Status'))),
          DataColumn(label: Text(s.text('Photo count', 'Număr fotografii'))),
          DataColumn(label: Text(s.text('Photo names', 'Fotografii'))),
          DataColumn(label: Text(s.text('Username', 'Utilizator'))),
        ],
        rows: [
          for (final item in items)
            (() {
              final report = Map<String, dynamic>.from(
                item['report'] as Map? ?? const {},
              );
              final names =
                  (report['photoNames'] as List?)?.cast<String>() ??
                      const <String>[];
              return DataRow(
                key: ValueKey('reportRow:${item['id']}'),
                cells: [
                  if (replacement) ...[
                    DataCell(Text(_number(report['oldX']))),
                    DataCell(Text(_number(report['oldY']))),
                    DataCell(Text(_number(report['newX']))),
                    DataCell(Text(_number(report['newY']))),
                    DataCell(Text(_serial(item, report, false, s))),
                    DataCell(Text(_serial(item, report, true, s))),
                  ] else ...[
                    DataCell(Text(_number(report['x']))),
                    DataCell(Text(_number(report['y']))),
                    DataCell(
                      Text(
                        kind == WorkKind.pit
                            ? '—'
                            : _serial(item, report, false, s),
                      ),
                    ),
                  ],
                  DataCell(
                    Text(workStatusLabel(s, report['status'] as String?)),
                  ),
                  DataCell(Text('${item['photoCount']}')),
                  DataCell(
                    SizedBox(
                      width: 260,
                      child: Tooltip(
                        message: names.join('\n'),
                        child: TextButton(
                          onPressed: () => onOpen(item['id'] as String),
                          child: Text(
                            names.isEmpty
                                ? s.text('Open photos', 'Deschide fotografiile')
                                : names.join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text('${item['owner']}')),
                ],
              );
            })(),
        ],
      ),
    );
  }
}