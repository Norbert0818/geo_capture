import 'package:flutter/material.dart';

import '../../core/widgets/control_safe_area.dart';
import '../../l10n/app_localizations.dart';
import '../uploads/upload_controller.dart';
import '../uploads/upload_panel.dart';
import 'capture_strings.dart';
import 'photo_draft_card.dart';
import 'photo_draft_store.dart';

class PhotoReviewSheet extends StatelessWidget {
  const PhotoReviewSheet({
    super.key,
    required this.drafts,
    this.uploads,
    this.promptForSerial = false,
  });

  final PhotoDraftStore drafts;
  final UploadController? uploads;
  final bool promptForSerial;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final labels = CaptureStrings.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([drafts, ?uploads]),
      builder: (context, _) {
        final busy = drafts.isCapturing || uploads?.isUploading == true;
        return PopScope(
          canPop: !busy,
          child: FractionallySizedBox(
            heightFactor: .92,
            child: ControlSafeArea(
              top: false,
              spacing: const EdgeInsets.fromLTRB(8, 0, 8, 24),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${t.pendingPhotos} (${drafts.items.length})',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('closePhotoReviewButton'),
                          tooltip: labels.close,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: busy
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('photoReviewList'),
                      padding: const EdgeInsets.all(12),
                      children: [
                        Text(t.draftNotice),
                        const SizedBox(height: 12),
                        if (uploads != null)
                          UploadPanel(
                            controller: uploads!,
                            promptForSerial: promptForSerial,
                          ),
                        if (drafts.items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              t.noPhotosYet,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        for (final photo in drafts.items)
                          PhotoDraftCard(
                            key: ValueKey(photo.id),
                            photo: photo,
                            onRemove: drafts.isLocked || busy
                                ? null
                                : () => drafts.remove(photo.id),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}