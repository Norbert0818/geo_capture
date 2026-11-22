import 'package:flutter/material.dart';

import '../capture/photo_draft_store.dart';

class DraftStoragePanel extends StatelessWidget {
  const DraftStoragePanel({super.key, required this.drafts});
  final PhotoDraftStore drafts;

  @override
  Widget build(BuildContext context) {
    if (!drafts.isPersistent) return const SizedBox.shrink();
    final ro = Localizations.localeOf(context).languageCode == 'ro';
    String text(String en, String translated) => ro ? translated : en;
    return AnimatedBuilder(
      animation: drafts,
      builder: (context, _) {
        final error = drafts.storageErrorCode;
        if (drafts.isRestoring) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              text(
                'Restoring saved photos...',
                'Se restaurează fotografiile salvate...',
              ),
            ),
          );
        }
        if (error == null) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              drafts.isSaving
                  ? text(
                'Saving on this device...',
                'Se salvează pe acest dispozitiv...',
              )
                  : text(
                'Drafts are saved on this device for your account.',
                'Ciornele sunt salvate pe acest dispozitiv pentru contul tău.',
              ),
              key: const ValueKey('localDraftStatus'),
            ),
          );
        }
        final conflict = error == 'local_drafts_conflict';
        final message = conflict
            ? text(
          'Drafts changed in another window. Reload the saved version to continue.',
          'Ciornele au fost schimbate în altă fereastră. Reîncarcă versiunea salvată pentru a continua.',
        )
            : !drafts.isReady
            ? text(
          'Saved drafts could not be read. They have not been overwritten. Try again.',
          'Ciornele salvate nu au putut fi citite. Nu au fost suprascrise. Încearcă din nou.',
        )
            : text(
          'Could not save on this device. Keep the app open and retry. Check the available storage space.',
          'Salvarea pe acest dispozitiv a eșuat. Păstrează aplicația deschisă și reîncearcă. Verifică spațiul disponibil.',
        );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  message,
                  key: const ValueKey('localDraftError'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('retryLocalDrafts'),
                  onPressed: drafts.isSaving || drafts.isRestoring
                      ? null
                      : () async {
                    if (conflict) {
                      final discard = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text(
                            text(
                              'Reload saved drafts?',
                              'Reîncarci ciornele salvate?',
                            ),
                          ),
                          content: Text(
                            text(
                              'Changes that were not saved in this window will be discarded. The saved version will be loaded.',
                              'Modificările nesalvate din această fereastră se vor pierde. Se va încărca versiunea salvată.',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: Text(text('Cancel', 'Anulează')),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: Text(text('Reload', 'Reîncarcă')),
                            ),
                          ],
                        ),
                      );
                      if (discard == true) await drafts.restore();
                    } else if (!drafts.isReady) {
                      await drafts.restore();
                    } else {
                      await drafts.flush();
                    }
                  },
                  child: Text(
                    conflict
                        ? text(
                      'Reload saved drafts',
                      'Reîncarcă ciornele salvate',
                    )
                        : text(
                      'Retry local save',
                      'Reîncearcă salvarea locală',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}