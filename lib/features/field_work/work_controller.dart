import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/api/api_client.dart';

import 'work_models.dart';
import 'work_repository.dart';
import 'work_storage.dart';

class WorkController extends ChangeNotifier {
  WorkController({
    required WorkDraft draft,
    required this.store,
    required this.repository,
    String Function()? newId,
  }) : _draft = draft,
        _newId = newId ?? const Uuid().v4;
  final WorkDraftStore store;
  final WorkRepository repository;
  final String Function() _newId;
  WorkDraft _draft;
  WorkDraft get draft => _draft;
  bool busy = false, saving = false, _disposed = false;
  String? error;
  Future<void> _writes = Future<void>.value();
  int _pendingWrites = 0;
  bool _localFailure = false;
  bool get locked => busy || draft.pendingChangeId != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> update(WorkDocument document, {String? reason}) {
    if (locked || _disposed) return Future.value();
    _draft = _draft.copyWith(document: document, reason: reason);
    return persist();
  }

  Future<void> persist() {
    final snapshot = _draft;
    _pendingWrites++;
    saving = true;
    _notify();
    _writes = _writes.then((_) async {
      if (_disposed) return;
      try {
        final revision = await store.write(
          snapshot.copyWith(localRevision: _draft.localRevision),
        );
        _draft = _draft.copyWith(localRevision: revision);
        _localFailure = false;
        error = null;
      } catch (failure) {
        _localFailure = true;
        error = failure.toString().contains('work_local_conflict')
            ? 'work_local_conflict'
            : 'work_local_save_failed';
      } finally {
        _pendingWrites--;
        saving = _pendingWrites > 0;
        _notify();
      }
    });
    return _writes;
  }

  Future<WorkDetails?> upload() async {
    if (busy || _disposed) return null;
    busy = true;
    _notify();
    try {
      await _writes;
      if (_localFailure ||
          !_draft.document.complete ||
          (_draft.expectedVersion != null && _draft.reason.trim().length < 3)) {
        return null;
      }
      error = null;
      if (_draft.pendingChangeId == null) {
        _draft = _draft.copyWith(pendingChangeId: _newId());
        try {
          final revision = await store.write(_draft);
          _draft = _draft.copyWith(localRevision: revision);
        } catch (_) {
          _localFailure = true;
          error = 'work_local_save_failed';
          return null;
        }
      }
      final frozen = _draft;
      final result = await repository.save(frozen);
      if (result.id != frozen.id ||
          result.version.isEmpty ||
          result.revision < 1 ||
          jsonEncode(result.document.toJson()) !=
              jsonEncode(frozen.document.toJson())) {
        throw StateError('work_invalid_acknowledgement');
      }
      await store.remove(_draft);
      return result;
    } catch (failure) {
      error = failure.toString();
      if (failure is ApiException &&
          failure.code.startsWith('work_') &&
          (failure.statusCode == 400 || failure.statusCode == 413)) {
        // A definite validation rejection did not commit a revision; editing is safe.
        _draft = WorkDraft(
          id: _draft.id,
          document: _draft.document,
          expectedVersion: _draft.expectedVersion,
          reason: _draft.reason,
          localRevision: _draft.localRevision,
        );
        try {
          _draft = _draft.copyWith(localRevision: await store.write(_draft));
        } catch (_) {
          _localFailure = true;
          error = 'work_local_save_failed';
        }
      }
      return null;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> reloadSaved() async {
    await _writes;
    final latest = (await store.readAll()).where(
          (value) => value.id == _draft.id,
    );
    if (latest.isEmpty) return false;
    _draft = latest.first;
    _localFailure = false;
    error = null;
    _notify();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}