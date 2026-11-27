import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'serial_reading.dart';
import 'work_models.dart';
import 'work_strings.dart';

class SerialDecision {
  const SerialDecision.confirm(this.identity) : takeLabel = false;
  const SerialDecision.labelPhoto() : identity = null, takeLabel = true;
  final PoleIdentity? identity;
  final bool takeLabel;
}

Future<SerialDecision?> confirmPhotoSerial(
    BuildContext context, {
      PoleIdentity? initial,
      SerialReading reading = const SerialReading(),
      Uint8List? image,
      String? photoId,
      bool allowLabelPhoto = true,
    }) => showDialog<SerialDecision>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SerialDialog(
    initial: initial,
    reading: reading,
    image: image,
    photoId: photoId,
    allowLabelPhoto: allowLabelPhoto,
  ),
);

class _SerialDialog extends StatefulWidget {
  const _SerialDialog({
    this.initial,
    required this.reading,
    this.image,
    this.photoId,
    required this.allowLabelPhoto,
  });
  final PoleIdentity? initial;
  final SerialReading reading;
  final Uint8List? image;
  final String? photoId;
  final bool allowLabelPhoto;
  @override
  State<_SerialDialog> createState() => _SerialDialogState();
}

class _SerialDialogState extends State<_SerialDialog> {
  final _serial = TextEditingController(), _ntet = TextEditingController();
  final _focus = FocusNode();
  String? _state;
  SerialCandidate? _selected;
  bool _invalid = false, _finished = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.reading.conflicting ? null : widget.reading.preferred;
    _serial.text = _selected?.serial ?? widget.initial?.serialNumber ?? '';
    _ntet.text = _selected?.ntet.isNotEmpty == true
        ? _selected!.ntet
        : widget.initial?.ntetCode ?? '';
    _state = _selected != null
        ? 'present'
        : widget.initial?.resolved == true
        ? widget.initial!.serialState ?? 'present'
        : null;
  }

  @override
  void dispose() {
    _serial.dispose();
    _ntet.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _finish(SerialDecision? decision) {
    if (_finished) return;
    _finished = true;
    Navigator.pop(context, decision);
  }

  void _confirm() {
    final serial = _state == 'missing' ? '' : _serial.text.trim();
    final candidate = _selected;
    final unchangedCandidate =
        candidate != null &&
            serial == candidate.serial &&
            (_ntet.text.trim() == candidate.ntet || candidate.ntet.isEmpty);
    final raw = unchangedCandidate ? candidate.raw : widget.initial?.rawCode;
    final identity = PoleIdentity(
      serialNumber: serial,
      ntetCode: _ntet.text.trim(),
      source: unchangedCandidate ? candidate.source : 'manual',
      rawCode: raw == null
          ? null
          : raw.substring(0, raw.length > 4096 ? 4096 : raw.length),
      serialState: _state,
      confirmed: true,
      evidencePhotoId: widget.photoId ?? widget.initial?.evidencePhotoId,
    );
    if (_state == null || !identity.valid) {
      setState(() => _invalid = true);
      return;
    }
    _finish(SerialDecision.confirm(identity));
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    return AlertDialog(
      title: Text(
        s.text(
          'Is the serial number correct?',
          'Numărul de serie este corect?',
        ),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.image != null)
                SizedBox(
                  height: 180,
                  child: InteractiveViewer(
                    maxScale: 8,
                    child: Image.memory(widget.image!, fit: BoxFit.contain),
                  ),
                ),
              if (_selected?.correctedCharacters == true)
                Text(
                  s.text(
                    'Some characters were interpreted as digits. Check the photograph carefully.',
                    'Unele caractere au fost interpretate ca cifre. Verifică atent fotografia.',
                  ),
                ),
              if (widget.reading.conflicting)
                Text(
                  s.text(
                    'Different numbers were found. Check the label and choose the correct one.',
                    'Au fost găsite numere diferite. Verifică eticheta și alege numărul corect.',
                  ),
                ),
              if (!widget.reading.supported)
                Text(
                  s.text(
                    'Automatic reading is available in the mobile app. You can enter the number here.',
                    'Citirea automată este disponibilă în aplicația mobilă. Poți introduce numărul aici.',
                  ),
                ),
              if (widget.reading.failed ||
                  widget.reading.candidates.isEmpty && widget.reading.supported)
                Text(
                  s.text(
                    'No reliable number was read. Photograph the label, enter the number or mark it missing/damaged.',
                    'Nu s-a citit o serie sigură. Fotografiază eticheta, introdu seria sau marchează lipsa/deteriorarea.',
                  ),
                ),
              if (widget.reading.candidates.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final candidate in widget.reading.candidates)
                      ActionChip(
                        key: ValueKey('serialCandidate:${candidate.serial}'),
                        label: Text(
                          '${candidate.serial} · ${candidate.source == 'scanned' ? 'QR' : 'OCR'}',
                        ),
                        onPressed: () => setState(() {
                          _selected = candidate;
                          _serial.text = candidate.serial;
                          if (candidate.ntet.isNotEmpty) {
                            _ntet.text = candidate.ntet;
                          }
                          _state = 'present';
                          _invalid = false;
                        }),
                      ),
                  ],
                ),
              if (widget.initial?.serialNumber.isNotEmpty == true)
                Text(
                  s.text(
                    'Previously saved: ${widget.initial!.serialNumber}',
                    'Salvat anterior: ${widget.initial!.serialNumber}',
                  ),
                ),
              for (final option in [
                (
                'present',
                s.text('The serial number exists', 'Există număr de serie'),
                ),
                (
                'missing',
                s.text(
                  'No serial number / label',
                  'Nu există serie / etichetă',
                ),
                ),
                (
                'damaged',
                s.text(
                  'Damaged / unreadable label',
                  'Etichetă deteriorată / ilizibilă',
                ),
                ),
              ])
                RadioListTile<String>(
                  key: ValueKey('serialState:${option.$1}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: option.$1,
                  groupValue: _state,
                  title: Text(option.$2),
                  onChanged: (value) => setState(() {
                    _state = value;
                    _invalid = false;
                  }),
                ),
              if (_state == 'present' || _state == 'damaged')
                TextField(
                  key: const ValueKey('confirmSerialNumber'),
                  controller: _serial,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: s.text(
                      _state == 'damaged'
                          ? 'Known serial (optional)'
                          : 'Serial number',
                      _state == 'damaged'
                          ? 'Serie cunoscută (opțional)'
                          : 'Număr de serie',
                    ),
                    helperText: s.text(
                      'Digits only. Leading zeros are preserved.',
                      'Doar cifre. Zerourile de la început se păstrează.',
                    ),
                  ),
                ),
              TextField(
                key: const ValueKey('confirmNtet'),
                controller: _ntet,
                maxLength: 128,
                decoration: InputDecoration(
                  labelText: s.text(
                    'NTET code (if available)',
                    'Cod NTET (dacă există)',
                  ),
                ),
              ),
              if (_invalid)
                Text(
                  s.text(
                    'Choose a label state. When a serial exists, enter digits.',
                    'Alege starea etichetei. Dacă seria există, introdu cifrele.',
                  ),
                  key: const ValueKey('serialConfirmationError'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.allowLabelPhoto)
          TextButton(
            key: const ValueKey('captureSerialLabel'),
            onPressed: () => _finish(const SerialDecision.labelPhoto()),
            child: Text(s.text('Photograph label', 'Fotografiază eticheta')),
          ),
        TextButton(
          key: const ValueKey('editReadSerial'),
          onPressed: () {
            setState(() => _state = 'present');
            _focus.requestFocus();
            _serial.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _serial.text.length,
            );
          },
          child: Text(s.text('No, edit', 'Nu, corectează')),
        ),
        TextButton(
          onPressed: () => _finish(null),
          child: Text(s.text('Later', 'Mai târziu')),
        ),
        FilledButton(
          key: const ValueKey('acceptPhotoSerial'),
          onPressed: _confirm,
          child: Text(s.text('Yes, save', 'Da, salvează')),
        ),
      ],
    );
  }
}