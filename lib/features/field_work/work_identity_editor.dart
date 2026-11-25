import 'package:flutter/material.dart';

import 'pole_code.dart';
import 'work_models.dart';
import 'work_qr_page.dart';
import 'work_strings.dart';

class WorkIdentityEditor extends StatefulWidget {
  const WorkIdentityEditor({
    super.key,
    required this.value,
    required this.onChanged,
    required this.isNewPole,
    required this.allowGeneration,
    required this.enabled,
  });
  final PoleIdentity value;
  final ValueChanged<PoleIdentity> onChanged;
  final bool isNewPole, allowGeneration, enabled;
  @override
  State<WorkIdentityEditor> createState() => _WorkIdentityEditorState();
}

class _WorkIdentityEditorState extends State<WorkIdentityEditor> {
  late final TextEditingController _serial = TextEditingController(
    text: widget.value.serialNumber,
  );
  late final TextEditingController _ntet = TextEditingController(
    text: widget.value.ntetCode,
  );
  String? _message;
  @override
  void didUpdateWidget(WorkIdentityEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_serial.text != widget.value.serialNumber) {
      _serial.text = widget.value.serialNumber;
    }
    if (_ntet.text != widget.value.ntetCode) _ntet.text = widget.value.ntetCode;
  }

  void _changed() {
    final value = PoleIdentity(
      serialNumber: _serial.text.trim(),
      ntetCode: _ntet.text.trim(),
      rawCode: widget.value.source == 'generated' ? null : widget.value.rawCode,
    );
    widget.onChanged(
      widget.isNewPole &&
          widget.allowGeneration &&
          widget.value.source == 'generated'
          ? value.generated()
          : value,
    );
  }

  Future<void> _scan() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const WorkQrScanPage()),
    );
    if (!mounted || raw == null) return;
    final s = WorkStrings.of(context);
    try {
      final result = PoleCode.read(raw);
      widget.onChanged(result);
      setState(
            () => _message = result.serialNumber.isEmpty
            ? s.text(
          'Code read. Enter the missing serial number and NTET code.',
          'Cod citit. Completează seria și codul NTET lipsă.',
        )
            : result.ntetCode.isEmpty
            ? s.text(
          'Serial read; this code contains no NTET value. Complete it if needed.',
          'Serie citită; acest cod nu conține NTET. Completează-l dacă este necesar.',
        )
            : null,
      );
    } on FormatException {
      setState(
            () => _message = s.text(
          'This code could not be interpreted. Enter the pole details manually.',
          'Codul nu poate fi interpretat. Introdu manual datele stâlpului.',
        ),
      );
    }
  }

  @override
  void dispose() {
    _serial.dispose();
    _ntet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: widget.enabled ? _scan : null,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(
            s.text(
              widget.isNewPole
                  ? 'Scan existing new QR'
                  : 'Scan old / existing code',
              widget.isNewPole
                  ? 'Scanează QR-ul nou existent'
                  : 'Scanează codul vechi / existent',
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _serial,
          enabled: widget.enabled,
          maxLength: 1024,
          decoration: InputDecoration(
            labelText: s.text(
              widget.isNewPole
                  ? 'New pole serial number'
                  : 'Existing / old pole serial number',
              widget.isNewPole
                  ? 'Serie stâlp nou'
                  : 'Serie stâlp existent / vechi',
            ),
            counterText: '',
          ),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ntet,
          enabled: widget.enabled,
          maxLength: 128,
          decoration: InputDecoration(
            labelText: s.text(
              widget.isNewPole ? 'New NTET code' : 'NTET code (if available)',
              widget.isNewPole ? 'Cod NTET nou' : 'Cod NTET (dacă există)',
            ),
            counterText: '',
          ),
          onChanged: (_) => _changed(),
        ),
        if (widget.isNewPole && widget.allowGeneration) ...[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const ValueKey('generatePoleQr'),
            onPressed:
            widget.enabled &&
                widget.value.valid &&
                widget.value.ntetCode.isNotEmpty
                ? () => widget.onChanged(widget.value.generated())
                : null,
            icon: const Icon(Icons.qr_code),
            label: Text(
              s.text(
                'Generate new QR from these values',
                'Generează QR nou din aceste valori',
              ),
            ),
          ),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(_message!),
          ),
        if (widget.value.rawCode != null) WorkQrCard(pole: widget.value),
      ],
    );
  }
}