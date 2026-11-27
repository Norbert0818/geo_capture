import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/widgets/control_safe_area.dart';
import '../capture/photo_draft.dart';
import 'pole_code.dart';
import 'romania_place_picker.dart';
import 'romania_places.dart';
import 'serial_confirmation.dart';
import 'serial_reader.dart';
import 'work_camera_page.dart';
import 'work_controller.dart';
import 'work_flow.dart';
import 'work_models.dart';
import 'work_photo_view.dart';
import 'work_qr_page.dart';
import 'work_repository.dart';
import 'work_review_page.dart';
import 'work_stamp_service.dart';
import 'work_storage.dart';
import 'work_strings.dart';

class WorkTaskServices {
  const WorkTaskServices({
    this.capture,
    this.reader,
    this.places,
    this.lookup,
    this.stamp,
    this.scanCode,
  });
  final Future<PhotoDraft?> Function(BuildContext context, String title)?
  capture;
  final SerialPhotoReader? reader;
  final Future<RomaniaPlaces> Function()? places;
  final Future<WorkPlace?> Function(WorkPhoto photo)? lookup;
  final Future<WorkPhoto> Function(WorkPhoto photo, Uint8List original)? stamp;
  final Future<String?> Function(BuildContext context)? scanCode;
}

class WorkTaskPage extends StatefulWidget {
  const WorkTaskPage({
    super.key,
    required this.draft,
    required this.store,
    required this.repository,
    required this.allowGeneration,
    this.services = const WorkTaskServices(),
  });
  final WorkDraft draft;
  final WorkDraftStore store;
  final WorkRepository repository;
  final bool allowGeneration;
  final WorkTaskServices services;
  @override
  State<WorkTaskPage> createState() => _WorkTaskPageState();
}

class _WorkTaskPageState extends State<WorkTaskPage> {
  late final _controller = WorkController(
    draft: widget.draft,
    store: widget.store,
    repository: widget.repository,
  );
  late final _reader = widget.services.reader ?? createSerialPhotoReader();
  late final _notes = TextEditingController(text: widget.draft.document.notes);
  late final _reason = TextEditingController(text: widget.draft.reason);
  final _scroll = ScrollController();
  RomaniaPlaces? _places;
  String? _placeError, _operationError;
  bool _processing = false, _reviewing = false, _generationRejected = false;
  int _step = 0;
  List<WorkFlowStep> get _steps => workFlowFor(_controller.draft.document);
  bool get _editable => !_processing && !_reviewing && !_controller.locked;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft.document.inProgress) {
      final first = _steps.indexWhere(
            (step) => !draft.document.photos.any((x) => x.role == step.key),
      );
      if (first >= 0) _step = first;
    }
    _controller.addListener(_changed);
    unawaited(_controller.persist());
    unawaited(_loadPlaces());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPlaces() async {
    try {
      final places = await (widget.services.places ?? RomaniaPlaces.load)();
      if (mounted) {
        setState(() {
          _places = places;
          _placeError = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _placeError = 'catalogue');
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    _notes.dispose();
    _reason.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _go(int index) {
    setState(() => _step = index.clamp(0, _steps.length - 1).toInt());
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  bool _newSide(String role) => role == 'new' || role == 'new_label';
  String _labelRole(bool isNew) =>
      _controller.draft.document.kind == WorkKind.replacement
          ? (isNew ? 'new_label' : 'old_label')
          : 'label';
  PoleIdentity? _identity(bool isNew) => isNew
      ? _controller.draft.document.newPole
      : _controller.draft.document.oldPole;
  Future<void> _setIdentity(bool isNew, PoleIdentity identity) =>
      _controller.update(
        _controller.draft.document.copyWith(
          oldPole: isNew ? null : identity,
          newPole: isNew ? identity : null,
        ),
      );

  Future<RomaniaPlace?> _placeFor(PhotoDraft draft) async {
    final places = _places!;
    for (final previous in _controller.draft.document.photos.reversed) {
      if (previous.countyCode != null &&
          Geolocator.distanceBetween(
            previous.location.latitude,
            previous.location.longitude,
            draft.location.latitude,
            draft.location.longitude,
          ) <=
              25) {
        return places.place(previous.localityCode) ??
            RomaniaPlace(
              countyCode: previous.countyCode!,
              county: previous.county,
              name: previous.locality,
            );
      }
    }
    final temporary = _photo(
      draft,
      'pit',
      const RomaniaPlace(countyCode: '', county: '', name: ''),
    );
    final lookedUp =
    await (widget.services.lookup ?? WorkPlaceService().lookup)(temporary);
    if (!mounted) return null;
    final matched = lookedUp == null
        ? null
        : places.match(lookedUp.locality, lookedUp.county);
    return matched ?? await pickRomaniaPlace(context, places);
  }

  WorkPhoto _photo(PhotoDraft draft, String role, RomaniaPlace place) =>
      WorkPhoto(
        id: draft.id,
        role: role,
        location: draft.location,
        capturedAt: draft.capturedAtUtc,
        utcOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
        locality: place.name,
        county: place.county,
        countyCode: place.countyCode,
        localityCode: place.code,
        placeSource: 'catalog',
        serialVisible: false,
        originalMimeType: draft.mimeType,
      );

  Future<void> _take(String role, {String? replaceId}) async {
    if (!_editable ||
        _places == null ||
        _controller.draft.document.photos.length >= 10 && replaceId == null) {
      return;
    }
    final s = WorkStrings.of(context);
    final isLabel = role.endsWith('_label') || role == 'label';
    final isNew = _newSide(role);
    bool takeLabelAfter = false;
    setState(() {
      _processing = true;
      _operationError = null;
    });
    try {
      final action = widget.services.capture;
      final draft = action != null
          ? await action(context, role)
          : await Navigator.push<PhotoDraft>(
        context,
        MaterialPageRoute(
          builder: (_) => WorkCameraPage(title: s.role(role)),
        ),
      );
      if (!mounted || draft == null) return;
      final needsSerial =
          _controller.draft.document.kind != WorkKind.pit &&
              (isLabel || _identity(isNew)?.resolved != true);
      final reading = needsSerial
          ? _reader
          .read(draft.originalBytes)
          .catchError(
            (Object _, StackTrace _) => const SerialReading(failed: true),
      )
          : Future.value(const SerialReading());
      final place = await _placeFor(draft);
      if (!mounted || place == null) return;
      final photo = await (widget.services.stamp ?? WorkStampService().stamp)(
        _photo(draft, role, place),
        draft.originalBytes,
      );
      if (!mounted) return;
      var document = _controller.draft.document;
      final photos = document.photos.where((x) => x.id != replaceId).toList()
        ..add(photo);
      document = _clearEvidence(document, replaceId).copyWith(photos: photos);
      await _controller.update(document);
      if (!mounted) return;
      if (needsSerial) {
        SerialReading result;
        try {
          result = await reading;
        } catch (_) {
          result = const SerialReading(failed: true);
        }
        if (!mounted) return;
        final decision = await confirmPhotoSerial(
          context,
          initial: _identity(isNew),
          reading: result,
          image: draft.originalBytes,
          photoId: photo.id,
        );
        if (!mounted) return;
        if (decision?.identity != null) {
          await _setIdentity(isNew, decision!.identity!);
        }
        takeLabelAfter = decision?.takeLabel == true;
      }
    } catch (failure) {
      if (mounted) setState(() => _operationError = failure.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
    if (mounted && takeLabelAfter) await _take(_labelRole(isNew));
  }

  WorkDocument _clearEvidence(WorkDocument document, String? id) {
    if (id == null) return document;
    return document.copyWith(
      oldPole: document.oldPole?.evidencePhotoId == id
          ? document.oldPole!.copyWith(clearEvidence: true)
          : null,
      newPole: document.newPole?.evidencePhotoId == id
          ? document.newPole!.copyWith(clearEvidence: true)
          : null,
    );
  }

  Future<void> _remove(WorkPhoto photo) async {
    final s = WorkStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.text('Delete photo?', 'Ștergi fotografia?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(s.text('Cancel', 'Anulează')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s.text('Delete', 'Șterge')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final document = _clearEvidence(_controller.draft.document, photo.id);
    await _controller.update(
      document.copyWith(
        photos: document.photos.where((x) => x.id != photo.id).toList(),
      ),
    );
  }

  Future<bool> _serial(bool isNew, {bool forceRead = false}) async {
    if (!_editable) return false;
    final document = _controller.draft.document;
    final roles = document.kind == WorkKind.replacement
        ? (isNew ? ['new_label', 'new'] : ['old_label', 'old'])
        : document.kind == WorkKind.repair
        ? ['label', 'before', 'after']
        : ['label', 'pole'];
    WorkPhoto? photo;
    for (final role in roles) {
      final found = document.photos.where((x) => x.role == role);
      if (found.isNotEmpty) {
        photo = found.last;
        break;
      }
    }
    bool takeLabel = false;
    bool resolved = false;
    setState(() => _processing = true);
    try {
      Uint8List? bytes;
      SerialReading reading = const SerialReading();
      if (photo != null && forceRead) {
        bytes =
            photo.original ??
                await widget.repository.image(
                  widget.draft.id,
                  photo.id,
                  original: true,
                );
        reading = await _reader.read(bytes);
      } else {
        bytes = photo?.original;
      }
      if (!mounted) return false;
      final decision = await confirmPhotoSerial(
        context,
        initial: _identity(isNew),
        reading: reading,
        image: bytes,
        photoId: photo?.id,
      );
      if (decision?.identity != null) {
        await _setIdentity(isNew, decision!.identity!);
        resolved = true;
      }
      takeLabel = decision?.takeLabel == true;
    } catch (failure) {
      if (mounted) setState(() => _operationError = failure.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
    if (mounted && takeLabel) await _take(_labelRole(isNew));
    return resolved || _identity(isNew)?.resolved == true;
  }

  Future<void> _scan(bool isNew) async {
    if (!_editable) return;
    var takeLabel = false;
    setState(() => _processing = true);
    try {
      final scan = widget.services.scanCode;
      final raw = scan != null
          ? await scan(context)
          : await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const WorkQrScanPage()),
      );
      if (!mounted || raw == null) return;
      final parsed = PoleCode.read(raw);
      final decision = await confirmPhotoSerial(
        context,
        initial: parsed.copyWith(
          serialNumber: PoleIdentity.numericSerial.hasMatch(parsed.serialNumber)
              ? parsed.serialNumber
              : '',
          serialState: 'pending',
          confirmed: false,
        ),
        reading: SerialReading(candidates: SerialCandidates.extract(qr: [raw])),
      );
      if (!mounted) return;
      if (decision?.identity != null) {
        await _setIdentity(isNew, decision!.identity!);
      }
      takeLabel = decision?.takeLabel == true;
    } catch (failure) {
      if (mounted) setState(() => _operationError = failure.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
    if (mounted && takeLabel) await _take(_labelRole(isNew));
  }

  Future<void> _save(bool finish) async {
    if (_processing || _reviewing || _controller.busy || _controller.saving) {
      return;
    }
    if (_controller.draft.pendingChangeId == null) {
      if (finish && _controller.draft.document.kind != WorkKind.pit) {
        if (_identity(false)?.resolved != true && !await _serial(false)) return;
        if (_controller.draft.document.kind == WorkKind.replacement &&
            _identity(true)?.resolved != true &&
            !await _serial(true)) {
          return;
        }
      }
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      await _controller.update(
        _controller.draft.document.copyWith(
          progress: finish ? 'completed' : 'in_progress',
        ),
        reason: _reason.text.trim().isEmpty && widget.draft.document.inProgress
            ? 'Continue work'
            : null,
      );
      if (!mounted || !_controller.draft.document.readyToSave) {
        if (mounted) {
          final invalid = firstInvalidWorkStep(_controller.draft);
          if (invalid != null) _go(invalid);
          _message(
            WorkStrings.of(context).text(
              'Add the required photos and confirm the serial state.',
              'Adaugă fotografiile obligatorii și confirmă starea seriei.',
            ),
          );
        }
        return;
      }
      if (_controller.draft.expectedVersion != null &&
          _controller.draft.reason.trim().length < 3) {
        _message(
          WorkStrings.of(context).text(
            'Enter a change reason (at least 3 characters).',
            'Introdu un motiv pentru modificare (minimum 3 caractere).',
          ),
        );
        return;
      }
      setState(() => _reviewing = true);
      WorkReviewDecision? decision;
      try {
        decision = await Navigator.push<WorkReviewDecision>(
          context,
          MaterialPageRoute(
            builder: (_) => WorkReviewPage(
              draft: _controller.draft,
              repository: widget.repository,
            ),
          ),
        );
      } finally {
        if (mounted) setState(() => _reviewing = false);
      }
      if (!mounted || decision == null) return;
      if (decision.editStep != null) {
        _go(decision.editStep!);
        return;
      }
    }
    final saved = await _controller.upload();
    if (!mounted) return;
    if (saved != null) {
      Navigator.pop(context, true);
      return;
    }
    if (_controller.error?.contains('work_qr_generation_disabled') == true) {
      setState(() => _generationRejected = true);
    }
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  Future<void> _changePlace(WorkPhoto photo) async {
    if (!_editable || _places == null) return;
    final place = await pickRomaniaPlace(
      context,
      _places!,
      initial: _places!.place(photo.localityCode),
      initialCountyCode: photo.countyCode,
    );
    if (place == null || !mounted) return;
    setState(() => _processing = true);
    try {
      final original =
          photo.original ??
              await widget.repository.image(
                widget.draft.id,
                photo.id,
                original: true,
              );
      final changed = WorkPhoto(
        id: const Uuid().v4(),
        role: photo.role,
        location: photo.location,
        capturedAt: photo.capturedAtUtc,
        utcOffsetMinutes: photo.utcOffsetMinutes,
        locality: place.name,
        county: place.county,
        countyCode: place.countyCode,
        localityCode: place.code,
        placeSource: 'catalog',
        serialVisible: false,
        originalMimeType: photo.originalMimeType,
      );
      final stamped = await (widget.services.stamp ?? WorkStampService().stamp)(
        changed,
        original,
      );
      final document = _clearEvidence(_controller.draft.document, photo.id);
      await _controller.update(
        document.copyWith(
          photos: document.photos
              .map((x) => x.id == photo.id ? stamped : x)
              .toList(),
        ),
      );
    } catch (failure) {
      if (mounted) setState(() => _operationError = failure.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _reloadLocal() async {
    final s = WorkStrings.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.text('Load the saved draft?', 'Încarci ciorna salvată?')),
        content: Text(
          s.text(
            'This replaces unsaved changes on this screen with the draft saved on this device.',
            'Modificările nesalvate de pe acest ecran vor fi înlocuite cu ciorna salvată pe dispozitiv.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(s.text('Cancel', 'Anulează')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s.text('Load saved draft', 'Încarcă ciorna salvată')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      setState(() => _step = 0);
      if (!await _controller.reloadSaved()) {
        throw StateError('work_local_save_failed');
      }
      _notes.text = _controller.draft.document.notes;
      _reason.text = _controller.draft.reason;
      if (mounted) _go(0);
    } catch (_) {
      if (mounted) _message(s.error('work_local_save_failed'));
    }
  }

  Future<void> _changeKind() async {
    final s = WorkStrings.of(context);
    final selected = await showDialog<WorkKind>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(s.text('Change work type', 'Schimbă tipul lucrării')),
        children: [
          for (final kind in WorkKind.values)
            if (kind != _controller.draft.document.kind)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, kind),
                child: Text(s.kind(kind)),
              ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.kind(selected)),
        content: Text(
          s.text(
            'Start this type with new photos and serial decisions? Notes are kept. Previously uploaded versions remain in history.',
            'Începi acest tip cu fotografii și serii noi? Observațiile se păstrează. Versiunile deja încărcate rămân în istoric.',
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
      WorkDocument(
        kind: selected,
        schemaVersion: 2,
        progress: 'in_progress',
        notes: _notes.text,
      ),
    );
    if (mounted) _go(0);
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context), document = _controller.draft.document;
    final step = _steps[_step];
    final isNew = step.newPole;
    final pole = _identity(isNew);
    final group = document.photos
        .where(
          (photo) =>
      workPhaseRoles(document, step.key).contains(photo.role) ||
          document.kind == WorkKind.repair && photo.role == 'label',
    )
        .toList();
    final busy = !_editable || _controller.saving;
    return PopScope(
      canPop:
      !_processing &&
          !_reviewing &&
          !_controller.busy &&
          !_controller.saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.kind(document.kind)),
          actions: [
            PopupMenuButton<String>(
              enabled: _editable,
              onSelected: (_) => _changeKind(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'kind',
                  child: Text(
                    s.text('Change work type', 'Schimbă tipul lucrării'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: ControlSafeArea(
          top: false,
          bottom: false,
          child: ListView(
            controller: _scroll,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    ChoiceChip(
                      key: ValueKey('taskPhase:${_steps[i].key}'),
                      label: Text(s.role(_steps[i].key)),
                      selected: i == _step,
                      onSelected: busy ? null : (_) => _go(i),
                    ),
                ],
              ),
              SizedBox(
                height: 28,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _processing
                        ? s.text(
                      'Preparing photo / reading label…',
                      'Se pregătește fotografia / se citește eticheta…',
                    )
                        : _controller.busy
                        ? s.text('Uploading…', 'Se încarcă…')
                        : _controller.saving
                        ? s.text(
                      'Saving on device…',
                      'Se salvează pe dispozitiv…',
                    )
                        : _controller.error?.contains('work_local') == true
                        ? s.text('Local save failed', 'Salvarea locală a eșuat')
                        : s.text('Saved on device', 'Salvat pe dispozitiv'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_placeError != null)
                ListTile(
                  title: Text(
                    s.text(
                      'Locality catalogue could not be loaded.',
                      'Catalogul localităților nu a putut fi încărcat.',
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _loadPlaces,
                    child: Text(s.text('Retry', 'Reîncearcă')),
                  ),
                ),
              if (_operationError != null || _controller.error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(s.error(_operationError ?? _controller.error)),
                  ),
                ),
              if (_controller.error?.contains('work_local') == true)
                TextButton(
                  onPressed: busy ? null : _controller.persist,
                  child: Text(
                    s.text('Retry local save', 'Reîncearcă salvarea locală'),
                  ),
                ),
              if (_controller.error == 'work_local_conflict')
                TextButton(
                  onPressed: busy ? null : _reloadLocal,
                  child: Text(
                    s.text('Load saved draft', 'Încarcă ciorna salvată'),
                  ),
                ),
              if (_controller.draft.pendingChangeId != null)
                FilledButton.icon(
                  key: const ValueKey('retryPendingTask'),
                  onPressed: _processing || _controller.busy
                      ? null
                      : () => _save(false),
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(
                    s.text(
                      'Retry pending upload',
                      'Reîncearcă încărcarea în așteptare',
                    ),
                  ),
                ),
              if (document.kind != WorkKind.pit)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          s.text(
                            isNew ? 'New pole' : 'Existing / old pole',
                            isNew ? 'Stâlp nou' : 'Stâlp existent / vechi',
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(s.serial(pole?.serialNumber, pole?.serialState)),
                        if (pole?.ntetCode.isNotEmpty == true)
                          Text('NTET: ${pole!.ntetCode}'),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              key: ValueKey(
                                'scanTaskQr:${isNew ? 'new' : 'old'}',
                              ),
                              onPressed: _editable ? () => _scan(isNew) : null,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: Text(
                                s.text(
                                  isNew
                                      ? 'Scan existing new QR'
                                      : 'Scan old / existing QR',
                                  isNew
                                      ? 'Scanează QR-ul nou existent'
                                      : 'Scanează QR-ul vechi / existent',
                                ),
                              ),
                            ),
                            TextButton(
                              key: ValueKey(
                                'editTaskSerial:${isNew ? 'new' : 'old'}',
                              ),
                              onPressed: _editable
                                  ? () => _serial(isNew)
                                  : null,
                              child: Text(
                                s.text(
                                  'Enter / correct serial',
                                  'Introdu / corectează seria',
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _editable && group.isNotEmpty
                                  ? () => _serial(isNew, forceRead: true)
                                  : null,
                              child: Text(
                                s.text(
                                  'Read from photo',
                                  'Citește din fotografie',
                                ),
                              ),
                            ),
                            if (isNew &&
                                widget.allowGeneration &&
                                !_generationRejected)
                              TextButton(
                                key: const ValueKey('taskGenerateQr'),
                                onPressed:
                                _editable &&
                                    pole?.valid == true &&
                                    pole!.serialNumber.isNotEmpty &&
                                    pole.ntetCode.isNotEmpty
                                    ? () => _setIdentity(true, pole.generated())
                                    : null,
                                child: Text(
                                  s.text('Generate new QR', 'Generează QR nou'),
                                ),
                              ),
                          ],
                        ),
                        if (pole?.source == 'generated')
                          WorkQrCard(pole: pole!),
                      ],
                    ),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: ValueKey('takeTaskPhoto:${step.key}'),
                    onPressed:
                    _editable &&
                        _places != null &&
                        document.photos.length < 10
                        ? () => _take(step.key)
                        : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(s.text('Take photo', 'Fotografiază')),
                  ),
                  if (document.kind != WorkKind.pit)
                    OutlinedButton.icon(
                      key: ValueKey('takeTaskLabel:${isNew ? 'new' : 'old'}'),
                      onPressed:
                      _editable &&
                          _places != null &&
                          document.photos.length < 10
                          ? () => _take(_labelRole(isNew))
                          : null,
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: Text(
                        s.text('Photograph label', 'Fotografiază eticheta'),
                      ),
                    ),
                ],
              ),
              for (final photo in group)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(s.role(photo.role)),
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
                          ),
                        ),
                        SelectableText(photo.overlayText),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: _editable
                                  ? () => _take(photo.role, replaceId: photo.id)
                                  : null,
                              child: Text(s.text('Retake', 'Refotografiază')),
                            ),
                            TextButton(
                              onPressed: _editable
                                  ? () => _changePlace(photo)
                                  : null,
                              child: Text(
                                s.text(
                                  'Change locality',
                                  'Schimbă localitatea',
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _editable
                                  ? () => _remove(photo)
                                  : null,
                              child: Text(s.text('Delete', 'Șterge')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (group.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    s.text(
                      'No photos in this phase yet.',
                      'Nu există încă fotografii în această etapă.',
                    ),
                  ),
                ),
              TextField(
                key: const ValueKey('taskNotes'),
                controller: _notes,
                enabled: _editable,
                minLines: 2,
                maxLines: 4,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: s.text('Notes', 'Observații'),
                ),
                onChanged: (value) => _controller.update(
                  _controller.draft.document.copyWith(notes: value),
                ),
              ),
              if (widget.draft.expectedVersion != null &&
                  !widget.draft.document.inProgress)
                TextField(
                  key: const ValueKey('taskChangeReason'),
                  controller: _reason,
                  enabled: _editable,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: s.text(
                      'Reason for change',
                      'Motivul modificării',
                    ),
                  ),
                  onChanged: (value) => _controller.update(
                    _controller.draft.document,
                    reason: value,
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        bottomNavigationBar: Material(
          elevation: 6,
          child: ControlSafeArea(
            top: false,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_step > 0)
                  TextButton(
                    onPressed: busy ? null : () => _go(_step - 1),
                    child: Text(s.text('Previous', 'Înapoi')),
                  ),
                OutlinedButton(
                  key: const ValueKey('saveTaskProgress'),
                  onPressed: busy || document.photos.isEmpty
                      ? null
                      : () => _save(false),
                  child: Text(
                    s.text(
                      'Save progress / continue later',
                      'Salvează progresul / continuă ulterior',
                    ),
                  ),
                ),
                if (_step + 1 < _steps.length)
                  FilledButton(
                    onPressed: busy ? null : () => _go(_step + 1),
                    child: Text(s.text('Next phase', 'Etapa următoare')),
                  )
                else
                  FilledButton(
                    key: const ValueKey('finishTask'),
                    onPressed: busy ? null : () => _save(true),
                    child: Text(
                      s.text('Finish and review', 'Finalizează și verifică'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}