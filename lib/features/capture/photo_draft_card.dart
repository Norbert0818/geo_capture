import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'photo_draft.dart';

class PhotoDraftCard extends StatefulWidget {
  const PhotoDraftCard({
    super.key,
    required this.photo,
    required this.onRemove,
  });

  final PhotoDraft photo;
  final VoidCallback onRemove;

  @override
  State<PhotoDraftCard> createState() => _PhotoDraftCardState();
}

class _PhotoDraftCardState extends State<PhotoDraftCard> {
  bool _showOriginal = false;

  String _date(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final romanian = t.localeName.toLowerCase().startsWith('ro');
    final photo = widget.photo;
    final stamped = photo.stamped;
    final originalLabel = romanian ? 'Originală' : 'Original';
    final stampedLabel = romanian ? 'Cu coordonate' : 'With coordinates';
    final previewLabel = romanian ? 'Deschide fotografia' : 'Open photo';
    final bytes = !_showOriginal && stamped != null
        ? stamped.bytes
        : photo.originalBytes;
    final title = !_showOriginal && stamped != null
        ? stampedLabel
        : originalLabel;

    void openPreview() {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              leading: IconButton(
                tooltip: MaterialLocalizations.of(
                  dialogContext,
                ).closeButtonTooltip,
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            body: ColoredBox(
              color: Colors.black,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 8,
                child: SizedBox.expand(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stamped != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    key: ValueKey('${photo.id}:coordinates'),
                    label: Text(stampedLabel),
                    selected: !_showOriginal,
                    onSelected: (_) => setState(() => _showOriginal = false),
                  ),
                  ChoiceChip(
                    key: ValueKey('${photo.id}:original'),
                    label: Text(originalLabel),
                    selected: _showOriginal,
                    onSelected: (_) => setState(() => _showOriginal = true),
                  ),
                ],
              ),
            ),
          InkWell(
            onTap: openPreview,
            child: Image.memory(
              bytes,
              height: 220,
              fit: BoxFit.contain,
              cacheWidth: 800,
              gaplessPlayback: true,
            ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: previewLabel,
                      onPressed: openPreview,
                      icon: const Icon(Icons.open_in_full),
                    ),
                    IconButton(
                      tooltip: t.removePhoto,
                      onPressed: widget.onRemove,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
