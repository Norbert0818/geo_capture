import 'package:flutter/material.dart';

import 'history_strings.dart';
import 'upload_history_models.dart';

class SerialNumbersView extends StatelessWidget {
  const SerialNumbersView({super.key, required this.summary});

  final UploadHistoryItem summary;

  @override
  Widget build(BuildContext context) {
    final t = HistoryStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: summary.hasSerialPair
          ? [
        Text('${t.oldSerial}: ${summary.oldSerialNumber}'),
        const SizedBox(height: 4),
        Text(
          '${t.newSerial}: ${summary.newSerialNumber}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ]
          : [
        Text(
          summary.serialNumber,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(t.legacySerial),
      ],
    );
  }
}