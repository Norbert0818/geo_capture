import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';

import '../../core/widgets/control_safe_area.dart';
import '../capture/photo_draft.dart';
import 'work_camera_page.dart';
import 'work_controller.dart';
import 'work_identity_editor.dart';
import 'work_models.dart';
import 'work_photo_view.dart';
import 'work_repository.dart';
import 'work_stamp_service.dart';
import 'work_storage.dart';
import 'work_strings.dart';
import 'work_flow.dart';
import 'work_review_page.dart';

typedef WorkPhotoCapture =
Future<PhotoDraft?> Function(BuildContext context, String role);

class WorkEditorPage extends StatefulWidget {
  const WorkEditorPage({
    super.key,
    required this.draft,
    required this.store,
    required this.repository,
    required this.allowGeneration,
    this.capturePhoto,
    this.lookupPlace,
    this.stampPhoto,
  });
  final WorkDraft draft;
  final WorkDraftStore store;
  final WorkRepository repository;
  final bool allowGeneration;
  final WorkPhotoCapture? capturePhoto;
  final Future<WorkPlace?> Function(WorkPhoto)? lookupPlace;
  final Future<WorkPhoto> Function(WorkPhoto, Uint8List)? stampPhoto;
  @override
  State<WorkEditorPage> createState() => _WorkEditorPageState();
}

class _WorkEditorPageState extends State<WorkEditorPage> {
  late final _controller = WorkController(
    draft: widget.draft,
    store: widget.store,
    repository: widget.repository,
  );
  final _placeService = WorkPlaceService();
  final _stamps = WorkStampService();
  int _step = 0;
  bool _processing = false;
  bool _reviewing = false;
  bool _generationRejected = false;
  @override
  void initState() {
    super.initState();
    if (widget.draft.localRevision == 0) _controller.persist();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<WorkFlowStep> get _flow => workFlow(_controller.draft.document.kind);

  bool _stepValid(int index) =>
      workStepComplete(_controller.draft.document, index);

  Future<bool?> _confirm(String message, PhotoDraft photo) => showDialog<bool>(
    context: context,
    builder: (dialog) {
      final s = WorkStrings.of(dialog);
      return AlertDialog(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InteractiveViewer(
                maxScale: 8,
                child: Image.memory(
                  photo.originalBytes,
                  height: 280,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              Text(message),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(s.text('No / retake', 'Nu / refă fotografia')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s.text('Yes', 'Da')),
          ),
        ],
      );
    },
  );

  Future<({String locality, String county, String source})?> _place(
      WorkPhoto photo,
      ) async {
    final suggestion = await (widget.lookupPlace ?? _placeService.lookup)(
      photo,
    );
    if (!mounted) return null;
    final result =
    await showDialog<({String locality, String county, String source})>(
      context: context,
      builder: (_) => _PlaceDialog(
        initialLocality: suggestion?.locality ?? photo.locality,
        initialCounty: suggestion?.county ?? photo.county,
        automatic: suggestion != null,
      ),
    );
    return result;
  }

  Future<void> _take(String role, {WorkPhoto? replace}) async {
    if (_processing || _controller.locked) return;
    final s = WorkStrings.of(context);
    setState(() => _processing = true);
    try {
      PhotoDraft? raw;
      while (mounted) {
        raw = widget.capturePhoto != null
            ? await widget.capturePhoto!(context, role)
            : await Navigator.push<PhotoDraft>(
          context,
          MaterialPageRoute(
            builder: (_) => WorkCameraPage(title: s.role(role)),
          ),
        );
        if (raw == null || !mounted) return;
        if (role != 'old') break;
        final visible = await _confirm(
          s.text(
            'Is the old pole serial number clearly visible in this photo?',
            'Seria stâlpului vechi este vizibilă clar în această fotografie?',
          ),
          raw,
        );
        if (visible == true) break;
        if (visible == null) return;
        if (!mounted) return;
      }
      if (raw == null || !mounted) return;
      final photo = WorkPhoto(
        id: raw.id,
        role: role,
        location: raw.location,
        capturedAt: raw.capturedAtUtc,
        utcOffsetMinutes: raw.capturedAtUtc.toLocal().timeZoneOffset.inMinutes,
        locality: '',
        county: '',
        placeSource: 'manual',
        serialVisible: role == 'old',
        originalMimeType: raw.mimeType,
      );
      final place = await _place(photo);
      if (place == null || !mounted) return;
      final ready = await (widget.stampPhoto ?? _stamps.stamp)(
        WorkPhoto(
          id: photo.id,
          role: role,
          location: photo.location,
          capturedAt: photo.capturedAtUtc,
          utcOffsetMinutes: photo.utcOffsetMinutes,
          locality: place.locality,
          county: place.county,
          placeSource: place.source,
          serialVisible: photo.serialVisible,
          originalMimeType: photo.originalMimeType,
        ),
        raw.originalBytes,
      );
      final photos = _controller.draft.document.photos.toList();
      final index = replace == null
          ? -1
          : photos.indexWhere((value) => value.id == replace.id);
      if (index < 0) {
        photos.add(ready);
      } else {
        photos[index] = ready;
      }
      await _controller.update(
        _controller.draft.document.copyWith(photos: photos),
      );
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.error(failure.toString()))));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _correctPlace(WorkPhoto old) async {
    if (_processing || _controller.locked) return;
    setState(() => _processing = true);
    try {
      final place =
      await showDialog<({String locality, String county, String source})>(
        context: context,
        builder: (_) => _PlaceDialog(
          initialLocality: old.locality,
          initialCounty: old.county,
          automatic: false,
        ),
      );
      if (place == null) return;
      final original =
          old.original ??
              await widget.repository.image(
                _controller.draft.id,
                old.id,
                original: true,
              );
      final changed = await (widget.stampPhoto ?? _stamps.stamp)(
        WorkPhoto(
          id: const Uuid().v4(),
          role: old.role,
          location: old.location,
          capturedAt: old.capturedAtUtc,
          utcOffsetMinutes: old.utcOffsetMinutes,
          locality: place.locality,
          county: place.county,
          placeSource: 'manual',
          serialVisible: old.serialVisible,
          originalMimeType: old.originalMimeType,
        ),
        original,
      );
      await _controller.update(
        _controller.draft.document.copyWith(
          photos: _controller.draft.document.photos
              .map((photo) => photo.id == old.id ? changed : photo)
              .toList(),
        ),
      );
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(WorkStrings.of(context).error(failure.toString())),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _delete(WorkPhoto photo) async {
    final s = WorkStrings.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        content: Text(
          s.text(
            'Remove this photo from the current version?',
            'Elimini fotografia din versiunea curentă?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(s.text('Cancel', 'Anulează')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s.text('Delete photo', 'Șterge fotografia')),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _controller.update(
        _controller.draft.document.copyWith(
          photos: _controller.draft.document.photos
              .where((value) => value.id != photo.id)
              .toList(),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (_processing || _reviewing || _controller.busy || _controller.saving) {
      return;
    }
    final draft = _controller.draft;
    if (draft.pendingChangeId == null) {
      final invalid = firstInvalidWorkStep(draft);
      if (invalid != null) {
        setState(() => _step = invalid);
        final s = WorkStrings.of(context);
        final reasonMissing =
            draft.document.complete &&
                draft.expectedVersion != null &&
                draft.reason.trim().length < 3;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reasonMissing
                  ? s.text(
                'Enter a change reason of at least 3 characters.',
                'Introdu un motiv de minimum 3 caractere pentru modificări.',
              )
                  : s.text(
                'Complete the required identifiers, photos and locations.',
                'Completează identificatorii, fotografiile și locațiile obligatorii.',
              ),
            ),
          ),
        );
        return;
      }
      if (_controller.error?.contains('work_local') == true) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _reviewing = true);
      WorkReviewDecision? decision;
      try {
        decision = await Navigator.push<WorkReviewDecision>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                WorkReviewPage(draft: draft, repository: widget.repository),
          ),
        );
      } finally {
        if (mounted) setState(() => _reviewing = false);
      }
      if (!mounted || decision == null) return;
      if (decision.editStep != null) {
        setState(
              () => _step = decision!.editStep!.clamp(0, _flow.length - 1).toInt(),
        );
        return;
      }
    }
    if (!mounted) return;
    final result = await _controller.upload();
    if (mounted &&
        _controller.error?.contains('work_qr_generation_disabled') == true) {
      setState(() => _generationRejected = true);
    }
    if (result != null && mounted) {
      Navigator.pop(context, true);
    } else if (mounted && _controller.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            WorkStrings.of(context).text(
              'Complete all required steps and the change reason.',
              'Completează pașii obligatorii și motivul modificării.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _changeKind(WorkKind kind) async {
    if (kind == _controller.draft.document.kind ||
        _controller.locked ||
        _processing) {
      return;
    }
    final s = WorkStrings.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        content: Text(
          s.text(
            'Changing the work type clears the pole details and photos in this draft. Uploaded history is kept.',
            'Schimbarea tipului golește datele stâlpilor și fotografiile din această ciornă. Istoricul încărcat este păstrat.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(s.text('Cancel', 'Anulează')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s.text('Change type', 'Schimbă tipul')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _step = 0);
    await _controller.update(
      WorkDocument(kind: kind, notes: _controller.draft.document.notes),
    );
  }

  Future<void> _reloadLocal() async {
    final s = WorkStrings.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        content: Text(
          s.text(
            'Reload the draft saved by the other window? Unsaved changes in this window will be discarded.',
            'Reîncarci ciorna salvată de cealaltă fereastră? Modificările nesalvate din această fereastră vor fi abandonate.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(s.text('Cancel', 'Anulează')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(
              s.text('Reload saved draft', 'Reîncarcă ciorna salvată'),
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _step = 0);
    try {
      final found = await _controller.reloadSaved();
      if (!found && mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.error(failure.toString()))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final draft = _controller.draft;
        final editable = !_processing && !_reviewing && !_controller.locked;
        return PopScope(
          canPop:
          !_processing &&
              !_controller.busy &&
              !_controller.saving &&
              _controller.error?.contains('work_local') != true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(s.kind(draft.document.kind)),
              actions: [
                if (editable)
                  PopupMenuButton<WorkKind>(
                    onSelected: _changeKind,
                    itemBuilder: (_) => [
                      for (final kind in WorkKind.values)
                        PopupMenuItem(value: kind, child: Text(s.kind(kind))),
                    ],
                  ),
              ],
            ),
            body: ControlSafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        key: const ValueKey('workSaveStatus'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            s.text(
                              'Original GPS and capture times are kept.',
                              'GPS-ul și ora originală sunt păstrate.',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _controller.saving
                                    ? Icons.save_outlined
                                    : Icons.check_circle_outline,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _controller.saving
                                      ? s.text(
                                    'Saving locally…',
                                    'Se salvează local…',
                                  )
                                      : s.text(
                                    'Draft saved locally',
                                    'Ciornă salvată local',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (draft.pendingChangeId != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            s.text(
                              'This upload is awaiting confirmation. Retry the same upload; its contents are frozen to prevent duplicates.',
                              'Încărcarea așteaptă confirmarea. Reîncearcă aceeași încărcare; conținutul este blocat pentru a preveni duplicatele.',
                            ),
                          ),
                        ),
                      ),
                    if (draft.pendingChangeId != null)
                      FilledButton.icon(
                        onPressed:
                        _controller.busy ||
                            _processing ||
                            _reviewing ||
                            _controller.saving
                            ? null
                            : _submit,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                          s.text(
                            'Retry pending upload',
                            'Reîncearcă încărcarea în așteptare',
                          ),
                        ),
                      ),
                    if (_controller.error != null)
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Text(s.error(_controller.error)),
                              if (_controller.error!.contains('work_local'))
                                TextButton(
                                  onPressed: _controller.saving
                                      ? null
                                      : _controller.persist,
                                  child: Text(
                                    s.text(
                                      'Retry local saving',
                                      'Reîncearcă salvarea locală',
                                    ),
                                  ),
                                ),
                              if (_controller.error!.contains(
                                'work_local_conflict',
                              ))
                                TextButton(
                                  onPressed: _reloadLocal,
                                  child: Text(
                                    s.text(
                                      'Reload saved draft',
                                      'Reîncarcă ciorna salvată',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    Stepper(
                      key: ValueKey(draft.document.kind),
                      physics: const NeverScrollableScrollPhysics(),
                      currentStep: _step,
                      onStepTapped: (index) {
                        if (editable &&
                            (index <= _step ||
                                List.generate(
                                  index,
                                  _stepValid,
                                ).every((valid) => valid))) {
                          setState(() => _step = index);
                        }
                      },
                      controlsBuilder: (_, details) =>
                      details.stepIndex != _step
                          ? const SizedBox.shrink()
                          : Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              key: const ValueKey('workContinue'),
                              onPressed:
                              _controller.busy ||
                                  _processing ||
                                  _reviewing ||
                                  _controller.saving
                                  ? null
                                  : _step == _flow.length - 1
                                  ? _submit
                                  : !_stepValid(_step) || !editable
                                  ? null
                                  : () => setState(() => _step++),
                              child: Text(
                                _step == _flow.length - 1
                                    ? s.text(
                                  'Review and upload',
                                  'Verifică și încarcă',
                                )
                                    : s.text('Continue', 'Continuă'),
                              ),
                            ),
                            if (_step > 0)
                              TextButton(
                                onPressed: editable
                                    ? () => setState(() => _step--)
                                    : null,
                                child: Text(s.text('Back', 'Înapoi')),
                              ),
                          ],
                        ),
                      ),
                      steps: List.generate(_flow.length, (index) {
                        final flow = _flow[index];
                        return Step(
                          title: Text(
                            flow.identity
                                ? s.text(
                              flow.newPole
                                  ? 'New pole identity'
                                  : 'Existing / old pole identity',
                              flow.newPole
                                  ? 'Date stâlp nou'
                                  : 'Date stâlp existent / vechi',
                            )
                                : s.role(flow.key),
                          ),
                          isActive: index == _step,
                          state: _stepValid(index)
                              ? StepState.complete
                              : StepState.indexed,
                          content: index != _step
                              ? const SizedBox.shrink()
                              : flow.identity
                              ? WorkIdentityEditor(
                            key: ValueKey(flow.key),
                            value:
                            (flow.newPole
                                ? draft.document.newPole
                                : draft.document.oldPole) ??
                                const PoleIdentity(),
                            isNewPole: flow.newPole,
                            allowGeneration:
                            widget.allowGeneration &&
                                !_generationRejected,
                            enabled: editable,
                            onChanged: (value) => _controller.update(
                              flow.newPole
                                  ? draft.document.copyWith(
                                newPole: value,
                              )
                                  : draft.document.copyWith(
                                oldPole: value,
                              ),
                            ),
                          )
                              : Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                            children: [
                              for (final photo
                              in draft.document.photos.where(
                                    (value) => value.role == flow.key,
                              ))
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      children: [
                                        InkWell(
                                          onTap: () => showWorkPhoto(
                                            context,
                                            photo,
                                            draft.id,
                                            widget.repository,
                                          ),
                                          child: WorkPhotoImage(
                                            photo: photo,
                                            workId: draft.id,
                                            repository: widget.repository,
                                          ),
                                        ),
                                        Text(photo.overlayText),
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            TextButton(
                                              onPressed: editable
                                                  ? () => _take(
                                                flow.key,
                                                replace: photo,
                                              )
                                                  : null,
                                              child: Text(
                                                s.text(
                                                  'Retake photo',
                                                  'Refă fotografia',
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: editable
                                                  ? () => _correctPlace(
                                                photo,
                                              )
                                                  : null,
                                              child: Text(
                                                s.text(
                                                  'Correct locality',
                                                  'Corectează localitatea',
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: editable
                                                  ? () => _delete(photo)
                                                  : null,
                                              child: Text(
                                                s.text(
                                                  'Delete photo',
                                                  'Șterge fotografia',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              OutlinedButton.icon(
                                key: ValueKey(
                                  'takeWorkPhoto:${flow.key}',
                                ),
                                onPressed:
                                editable &&
                                    draft.document.photos.length < 10
                                    ? () => _take(flow.key)
                                    : null,
                                icon: const Icon(
                                  Icons.camera_alt_outlined,
                                ),
                                label: Text(
                                  s.text(
                                    'Take / add photo',
                                    'Fotografiază / adaugă poză',
                                  ),
                                ),
                              ),
                              if (index == _flow.length - 1) ...[
                                const SizedBox(height: 16),
                                TextFormField(
                                  initialValue: draft.document.notes,
                                  enabled: editable,
                                  maxLength: 4000,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: InputDecoration(
                                    labelText: s.text(
                                      'Notes',
                                      'Observații',
                                    ),
                                  ),
                                  onChanged: (value) =>
                                      _controller.update(
                                        _controller.draft.document
                                            .copyWith(notes: value),
                                      ),
                                ),
                                if (draft.expectedVersion != null)
                                  TextFormField(
                                    initialValue: draft.reason,
                                    enabled: editable,
                                    maxLength: 500,
                                    decoration: InputDecoration(
                                      labelText: s.text(
                                        'Reason for change (required)',
                                        'Motivul modificării (obligatoriu)',
                                      ),
                                    ),
                                    onChanged: (value) =>
                                        _controller.update(
                                          _controller.draft.document,
                                          reason: value,
                                        ),
                                  ),
                              ],
                            ],
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaceDialog extends StatefulWidget {
  const _PlaceDialog({
    required this.initialLocality,
    required this.initialCounty,
    required this.automatic,
  });
  final String initialLocality, initialCounty;
  final bool automatic;
  @override
  State<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<_PlaceDialog> {
  late final _locality = TextEditingController(text: widget.initialLocality);
  late final _county = TextEditingController(text: widget.initialCounty);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _locality.dispose();
    _county.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    String? requiredValue(String? value) => value?.trim().isNotEmpty == true
        ? null
        : s.text('Required', 'Obligatoriu');
    return AlertDialog(
      title: Text(s.text('Photo location', 'Localizarea fotografiei')),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.text(
                  'Confirm the locality and county at the measured GPS point.',
                  'Confirmă localitatea și județul punctului GPS măsurat.',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locality,
                maxLength: 160,
                validator: requiredValue,
                decoration: InputDecoration(
                  labelText: s.text('Village / town', 'Sat / oraș'),
                ),
              ),
              TextFormField(
                controller: _county,
                maxLength: 160,
                validator: requiredValue,
                decoration: InputDecoration(
                  labelText: s.text('County', 'Județ'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.text('Cancel', 'Anulează')),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final automatic =
                widget.automatic &&
                    _locality.text.trim() == widget.initialLocality &&
                    _county.text.trim() == widget.initialCounty;
            Navigator.pop(context, (
            locality: _locality.text.trim(),
            county: _county.text.trim(),
            source: automatic ? 'geocoder' : 'manual',
            ));
          },
          child: Text(s.text('Use on photo', 'Aplică pe fotografie')),
        ),
      ],
    );
  }
}