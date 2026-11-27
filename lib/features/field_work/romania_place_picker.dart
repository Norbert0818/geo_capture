import 'package:flutter/material.dart';

import '../../core/widgets/control_safe_area.dart';
import 'romania_places.dart';
import 'work_strings.dart';

Future<RomaniaPlace?> pickRomaniaPlace(
    BuildContext context,
    RomaniaPlaces places, {
      RomaniaPlace? initial,
      String? initialCountyCode,
      bool allowManual = true,
    }) => showModalBottomSheet<RomaniaPlace>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _PlacePicker(
    places: places,
    initial: initial,
    initialCountyCode: initialCountyCode,
    allowManual: allowManual,
  ),
);

class _PlacePicker extends StatefulWidget {
  const _PlacePicker({
    required this.places,
    this.initial,
    this.initialCountyCode,
    required this.allowManual,
  });
  final RomaniaPlaces places;
  final RomaniaPlace? initial;
  final String? initialCountyCode;
  final bool allowManual;
  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  final _query = TextEditingController();
  String? _county;
  @override
  void initState() {
    super.initState();
    _county = widget.initial?.countyCode ?? widget.initialCountyCode;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    final results = widget.places.search(_query.text, countyCode: _county);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: ControlSafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.text('Choose locality', 'Alege localitatea'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('placeCounty:${_county ?? 'all'}'),
                initialValue: _county,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: s.text('County', 'Județ'),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(s.text('All counties', 'Toate județele')),
                  ),
                  for (final county in widget.places.counties)
                    DropdownMenuItem(
                      value: county.code,
                      child: Text(county.name),
                    ),
                ],
                onChanged: (value) => setState(() => _county = value),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('placeSearch'),
                controller: _query,
                maxLength: 160,
                decoration: InputDecoration(
                  labelText: s.text(
                    'Search town / village',
                    'Caută oraș / sat',
                  ),
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              Text(
                s.text(
                  'Names can repeat; check the commune and county.',
                  'Numele se pot repeta; verifică UAT-ul și județul.',
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final place = results[index];
                    return ListTile(
                      key: ValueKey('place:${place.code}'),
                      title: Text(place.name),
                      subtitle: Text('${place.unit} · ${place.county}'),
                      onTap: () => Navigator.pop(context, place),
                    );
                  },
                ),
              ),
              if (widget.allowManual &&
                  _county != null &&
                  _query.text.trim().isNotEmpty)
                TextButton(
                  key: const ValueKey('manualRomaniaPlace'),
                  onPressed: () {
                    final county = widget.places.county(_county)!;
                    Navigator.pop(
                      context,
                      RomaniaPlace(
                        countyCode: county.code,
                        county: county.name,
                        name: _query.text.trim(),
                      ),
                    );
                  },
                  child: Text(
                    s.text(
                      'Use typed locality in this county',
                      'Folosește localitatea introdusă în acest județ',
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(s.text('Cancel', 'Anulează')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}