import 'package:flutter/material.dart';

import '../../core/widgets/control_safe_area.dart';
import 'work_flow.dart';
import 'work_models.dart';
import 'work_photo_view.dart';
import 'work_repository.dart';
import 'work_strings.dart';

class WorkReviewDecision {
  const WorkReviewDecision.confirm() : editStep = null;
  const WorkReviewDecision.edit(int step) : editStep = step;
  final int? editStep;
}

class WorkReviewPage extends StatefulWidget {
  const WorkReviewPage({
    super.key,
    required this.draft,
    required this.repository,
  });
  final WorkDraft draft;
  final WorkRepository repository;
  @override
  State<WorkReviewPage> createState() => _WorkReviewPageState();
}

class _WorkReviewPageState extends State<WorkReviewPage> {
  bool _decided = false;

  void _finish(WorkReviewDecision? decision) {
    if (_decided) return;
    if (decision != null &&
        decision.editStep == null &&
        firstInvalidWorkStep(widget.draft) != null) {
      return;
    }
    _decided = true;
    Navigator.pop(context, decision);
  }

  Widget _edit(int step, WorkStrings s, String key) => TextButton.icon(
    key: ValueKey(key),
    onPressed: () => _finish(WorkReviewDecision.edit(step)),
    icon: const Icon(Icons.edit_outlined),
    label: Text(s.text('Edit', 'Modifică')),
  );

  String _source(PoleIdentity pole, WorkStrings s) => switch (pole.source) {
    'scanned' => s.text('Scanned code', 'Cod scanat'),
    'generated' => s.text('Generated QR code', 'Cod QR generat'),
    _ => s.text('Entered manually', 'Introduse manual'),
  };

  Widget _phase(WorkFlowStep step, int index, WorkStrings s) {
    final document = widget.draft.document;
    final pole = step.newPole ? document.newPole : document.oldPole;
    final title = step.identity
        ? (step.newPole
        ? s.text('New pole', 'Stâlp nou')
        : s.text('Existing / old pole', 'Stâlp existent / vechi'))
        : s.role(step.key);
    return Card(
      key: ValueKey('reviewPhase:${step.key}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  workStepComplete(document, index)
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _edit(index, s, 'editReview:${step.key}'),
              ],
            ),
            if (step.identity) ...[
              const SizedBox(height: 8),
              Text(s.text('Serial number', 'Număr de serie')),
              SelectableText(
                pole?.serialNumber ?? '—',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(s.text('NTET code', 'Cod NTET')),
              SelectableText(
                pole?.ntetCode.isNotEmpty == true ? pole!.ntetCode : '—',
              ),
              if (pole != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_source(pole, s)),
                ),
            ] else ...[
              for (final photo in document.photos.where(
                    (photo) => photo.role == step.key,
              ))
                Padding(
                  key: ValueKey('reviewPhoto:${photo.id}'),
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: () => showWorkPhoto(
                          context,
                          photo,
                          widget.draft.id,
                          widget.repository,
                        ),
                        child: WorkPhotoImage(
                          photo: photo,
                          workId: widget.draft.id,
                          repository: widget.repository,
                          height: 220,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(photo.overlayText),
                      Text(
                        '${s.text('Location accuracy', 'Precizia locației')}: ${photo.location.accuracyMeters.toStringAsFixed(1)} m',
                      ),
                      if (photo.role == 'old')
                        Text(
                          photo.serialVisible
                              ? s.text(
                            'Serial visibility confirmed',
                            'Vizibilitatea seriei confirmată',
                          )
                              : s.text(
                            'Serial visibility needs confirmation',
                            'Vizibilitatea seriei trebuie confirmată',
                          ),
                        ),
                    ],
                  ),
                ),
              if (!document.photos.any((photo) => photo.role == step.key))
                Text(
                  s.text(
                    'Required photo is missing.',
                    'Lipsește fotografia obligatorie.',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    final draft = widget.draft;
    final document = draft.document;
    final steps = workFlow(document.kind);
    final invalid = firstInvalidWorkStep(draft);
    final revision = draft.expectedVersion != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.text('Review before upload', 'Verifică înainte de încărcare'),
        ),
      ),
      body: ControlSafeArea(
        top: false,
        bottom: false,
        spacing: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              key: const ValueKey('workReviewList'),
              children: [
                Text(
                  s.kind(document.kind),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${s.text('Photos', 'Fotografii')}: ${document.photos.length}',
                ),
                Text(
                  s.text(
                    'Check the identifiers, photo roles and locations. Tap a photo to inspect both versions.',
                    'Verifică identificatorii, rolurile fotografiilor și locațiile. Atinge o fotografie pentru a vedea ambele variante.',
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < steps.length; index++)
                  _phase(steps[index], index, s),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.text('Notes', 'Observații'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            _edit(steps.length - 1, s, 'editReview:notes'),
                          ],
                        ),
                        SelectableText(
                          document.notes.trim().isEmpty ? '—' : document.notes,
                        ),
                        if (revision) ...[
                          const Divider(),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s.text(
                                    'Reason for change',
                                    'Motivul modificării',
                                  ),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              _edit(steps.length - 1, s, 'editReview:reason'),
                            ],
                          ),
                          SelectableText(draft.reason),
                          Text(
                            s.text(
                              'Saving creates a new version in the change history.',
                              'Salvarea creează o versiune nouă în istoricul modificărilor.',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Material(
        elevation: 6,
        child: ControlSafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (invalid != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        s.text(
                          'Complete the required data before uploading.',
                          'Completează datele obligatorii înainte de încărcare.',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        key: const ValueKey('cancelWorkReview'),
                        onPressed: () => _finish(null),
                        child: Text(
                          s.text('Back to editing', 'Înapoi la editare'),
                        ),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('confirmWorkUpload'),
                        onPressed: invalid == null
                            ? () => _finish(const WorkReviewDecision.confirm())
                            : null,
                        icon: Icon(
                          revision
                              ? Icons.save_outlined
                              : Icons.cloud_upload_outlined,
                        ),
                        label: Text(
                          revision
                              ? s.text(
                            'Save new revision',
                            'Salvează versiunea nouă',
                          )
                              : s.text('Upload work', 'Încarcă lucrarea'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}