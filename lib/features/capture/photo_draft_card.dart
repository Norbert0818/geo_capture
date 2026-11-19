import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'photo_draft.dart';

class PhotoDraftCard extends StatelessWidget {
  const PhotoDraftCard({
    super.key,
    required this.photo,
    required this.onRemove,
  });

  final PhotoDraft photo;
  final VoidCallback onRemove;

  String _date(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Image.memory(
            photo.originalBytes,
            height: 200,
            fit: BoxFit.contain,
            cacheWidth: 800,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  photo.location.overlayText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('${t.capturedAt}: ${_date(photo.capturedAtUtc)}'),
                Text(
                  '${t.locationMeasuredAt}: '
                      '${_date(photo.location.measuredAtUtc)}',
                ),
                Text(
                  '${t.locationAccuracy}: '
                      '${photo.location.accuracyMeters.toStringAsFixed(1)} m',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: t.removePhoto,
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}