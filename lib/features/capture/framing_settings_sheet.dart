import 'package:flutter/material.dart';

import '../../core/widgets/control_safe_area.dart';
import 'camera_framing.dart';

class FramingSettingsSheet extends StatefulWidget {
  const FramingSettingsSheet({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  final CameraFraming initialValue;
  final ValueChanged<CameraFraming> onChanged;

  @override
  State<FramingSettingsSheet> createState() => _FramingSettingsSheetState();
}

class _FramingSettingsSheetState extends State<FramingSettingsSheet> {
  late CameraFraming _value = widget.initialValue;

  void _change(CameraFraming value) {
    setState(() => _value = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final ro = Localizations.localeOf(context).languageCode == 'ro';
    String text(String en, String translated) => ro ? translated : en;
    Widget slider(
        String key,
        String label,
        int value,
        int max,
        ValueChanged<int> changed,
        ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $value%'),
        Slider(
          key: ValueKey(key),
          value: value.toDouble(),
          max: max.toDouble(),
          divisions: max > 0 ? max : null,
          label: '$value%',
          onChanged: max == 0 ? null : (next) => changed(next.round()),
        ),
      ],
    );

    return ControlSafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    text('Camera framing', 'Încadrare cameră'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const ValueKey('closeFramingSettings'),
                  tooltip: text('Close', 'Închide'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            slider(
              'topFramingSlider',
              text('Top shaded area', 'Zona întunecată de sus'),
              _value.topPercent,
              90 - _value.bottomPercent,
                  (value) => _change(_value.copyWith(top: value)),
            ),
            slider(
              'bottomFramingSlider',
              text('Bottom shaded area', 'Zona întunecată de jos'),
              _value.bottomPercent,
              90 - _value.topPercent,
                  (value) => _change(_value.copyWith(bottom: value)),
            ),
            slider(
              'framingOpacitySlider',
              text('Darkness', 'Intensitate întunecare'),
              _value.opacityPercent,
              100,
                  (value) => _change(_value.copyWith(opacity: value)),
            ),
            Text(
              text(
                'Clear area: ${_value.clearPercent}%',
                'Zona liberă: ${_value.clearPercent}%',
              ),
              key: const ValueKey('clearFramingArea'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('resetFramingSettings'),
              onPressed: () => _change(const CameraFraming()),
              child: Text(
                text('Reset defaults', 'Restabilește valorile inițiale'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}