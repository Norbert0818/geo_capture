import 'package:flutter/material.dart';

import 'work_list_filters.dart';
import 'work_models.dart';
import 'work_strings.dart';

class WorkListFilterPanel extends StatefulWidget {
  const WorkListFilterPanel({
    super.key,
    required this.filters,
    required this.showOwner,
    required this.busy,
    required this.onApply,
  });
  final WorkListFilters filters;
  final bool showOwner, busy;
  final ValueChanged<WorkListFilters> onApply;

  @override
  State<WorkListFilterPanel> createState() => _WorkListFilterPanelState();
}

class _WorkListFilterPanelState extends State<WorkListFilterPanel> {
  final _serial = TextEditingController(),
      _ntet = TextEditingController(),
      _locality = TextEditingController(),
      _county = TextEditingController(),
      _owner = TextEditingController();
  WorkKind? _kind;
  String _fromDate = '', _toDate = '';
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  void _read() {
    final value = widget.filters;
    _kind = value.kind;
    _serial.text = value.serial;
    _ntet.text = value.ntet;
    _locality.text = value.locality;
    _county.text = value.county;
    _owner.text = widget.showOwner ? value.owner : '';
    _fromDate = value.fromDate;
    _toDate = value.toDate;
    _invalid = false;
  }

  @override
  void didUpdateWidget(covariant WorkListFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters != widget.filters) _read();
    if (!widget.showOwner) _owner.clear();
  }

  @override
  void dispose() {
    for (final controller in [_serial, _ntet, _locality, _county, _owner]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _apply() {
    final value = WorkListFilters(
      kind: _kind,
      serial: _serial.text.trim(),
      ntet: _ntet.text.trim(),
      locality: _locality.text.trim(),
      county: _county.text.trim(),
      owner: widget.showOwner ? _owner.text.trim() : '',
      fromDate: _fromDate,
      toDate: _toDate,
    );
    setState(() => _invalid = !value.validDates);
    if (!_invalid) widget.onApply(value);
  }

  Future<void> _pickDate(bool from) async {
    final current = from ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _fromDate = WorkListFilters.date(picked);
      } else {
        _toDate = WorkListFilters.date(picked);
      }
      _invalid = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    return Card(
      child: ExpansionTile(
        key: const PageStorageKey('workFilters'),
        leading: const Icon(Icons.filter_alt_outlined),
        title: Text(s.text('Search uploaded work', 'Caută lucrări încărcate')),
        subtitle: Text(
          widget.filters.isEmpty
              ? s.text(
            'Type, serial, NTET, place and capture date',
            'Tip, serie, NTET, localitate și data fotografiei',
          )
              : s.text('Filters applied', 'Filtre aplicate'),
        ),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth < 600
                  ? box.maxWidth
                  : (box.maxWidth - 12) / 2;
              Widget field(
                  String key,
                  TextEditingController controller,
                  String label,
                  int max,
                  ) => SizedBox(
                key: PageStorageKey(key),
                width: width,
                child: TextField(
                  key: ValueKey(key),
                  controller: controller,
                  maxLength: max,
                  decoration: InputDecoration(
                    labelText: label,
                    counterText: '',
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    if (!widget.busy) _apply();
                  },
                ),
              );
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('workKind:${_kind?.name ?? 'any'}'),
                      initialValue: _kind?.name ?? 'any',
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: s.text('Work type', 'Tip lucrare'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'any',
                          child: Text(s.text('All types', 'Toate tipurile')),
                        ),
                        for (final kind in WorkKind.values)
                          DropdownMenuItem(
                            value: kind.name,
                            child: Text(s.kind(kind)),
                          ),
                      ],
                      onChanged: (value) => setState(
                            () => _kind = value == 'any' || value == null
                            ? null
                            : WorkKind.values.byName(value),
                      ),
                    ),
                  ),
                  field(
                    'workFilterSerial',
                    _serial,
                    s.text('Old or new serial number', 'Serie veche sau nouă'),
                    1024,
                  ),
                  field(
                    'workFilterNtet',
                    _ntet,
                    s.text('NTET code', 'Cod NTET'),
                    128,
                  ),
                  field(
                    'workFilterLocality',
                    _locality,
                    s.text('Locality', 'Localitate'),
                    160,
                  ),
                  field(
                    'workFilterCounty',
                    _county,
                    s.text('County', 'Județ'),
                    160,
                  ),
                  if (widget.showOwner)
                    field(
                      'workFilterOwner',
                      _owner,
                      s.text('Username', 'Utilizator'),
                      256,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              s.text(
                'Photo capture date (inclusive)',
                'Data fotografiei (inclusiv)',
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('workFilterFrom'),
                onPressed: () => _pickDate(true),
                icon: const Icon(Icons.calendar_today),
                label: Text(
                  '${s.text('From', 'De la')}: ${_fromDate.isEmpty ? '—' : _fromDate}',
                ),
              ),
              if (_fromDate.isNotEmpty)
                IconButton(
                  tooltip: s.text('Clear start date', 'Șterge data de început'),
                  onPressed: () => setState(() => _fromDate = ''),
                  icon: const Icon(Icons.close),
                ),
              OutlinedButton.icon(
                key: const ValueKey('workFilterTo'),
                onPressed: () => _pickDate(false),
                icon: const Icon(Icons.calendar_today),
                label: Text(
                  '${s.text('To', 'Până la')}: ${_toDate.isEmpty ? '—' : _toDate}',
                ),
              ),
              if (_toDate.isNotEmpty)
                IconButton(
                  tooltip: s.text('Clear end date', 'Șterge data de sfârșit'),
                  onPressed: () => setState(() => _toDate = ''),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_invalid)
            Text(
              s.text(
                'The end date must be on or after the start date.',
                'Data de sfârșit trebuie să fie după sau egală cu data de început.',
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('applyWorkFilters'),
                onPressed: widget.busy ? null : _apply,
                icon: const Icon(Icons.search),
                label: Text(s.text('Apply filters', 'Aplică filtrele')),
              ),
              TextButton(
                key: const ValueKey('clearWorkFilters'),
                onPressed: widget.busy
                    ? null
                    : () => widget.onApply(const WorkListFilters()),
                child: Text(s.text('Clear filters', 'Șterge filtrele')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}