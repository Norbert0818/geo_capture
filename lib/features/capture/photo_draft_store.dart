import 'package:flutter/foundation.dart';

import '../drafts/draft_snapshot.dart';
import '../uploads/upload_batch.dart';
import 'photo_draft.dart';

class PhotoDraftStore extends ChangeNotifier {
  PhotoDraftStore({this.persistence}) : _ready = persistence == null;

  final DraftPersistence? persistence;
  final _items = <PhotoDraft>[];
  bool _ready;
  bool _restoring = false;
  bool _capturing = false;
  bool _locked = false;
  bool _disposed = false;
  bool _saving = false;
  int _revision = 0;
  int _generation = 0;
  int _savedGeneration = 0;
  Future<bool>? _saveWork;
  DraftSnapshot? _closingSnapshot;
  String? _errorCode;
  String? _storageError;
  String _oldSerial = '';
  String _newSerial = '';
  UploadBatch? _pending;

  List<PhotoDraft> get items => List.unmodifiable(_items);
  bool get isPersistent => persistence != null;
  bool get isReady => _ready;
  bool get isRestoring => _restoring;
  bool get isSaving => _saving;
  bool get hasUnsavedChanges => isPersistent && _generation != _savedGeneration;
  bool get isCapturing => _capturing;
  bool get isLocked => _locked || !_ready || _storageError != null;
  String? get errorCode => _errorCode;
  String? get storageErrorCode => _storageError;
  String get oldSerialNumber => _oldSerial;
  String get newSerialNumber => _newSerial;
  UploadBatch? get pendingBatch => _pending;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  DraftSnapshot _snapshot() => DraftSnapshot(
    photos: _items,
    oldSerialNumber: _oldSerial,
    newSerialNumber: _newSerial,
    pendingUploadId: _pending?.id,
  );

  void _apply(StoredDrafts stored) {
    final pending = stored.snapshot.pendingBatch;
    _items
      ..clear()
      ..addAll(stored.snapshot.photos);
    _oldSerial = stored.snapshot.oldSerialNumber;
    _newSerial = stored.snapshot.newSerialNumber;
    _pending = pending;
    _locked = pending != null;
    _revision = stored.revision;
    _generation = _savedGeneration = 0;
    _storageError = null;
    _ready = true;
  }

  Future<void> restore() async {
    if (_disposed || _restoring || _saving || _capturing) return;
    final source = persistence;
    if (source == null) return;
    _restoring = true;
    _ready = false;
    _notify();
    try {
      final stored = await source.read();
      if (!_disposed) _apply(stored);
    } on DraftStorageException catch (error) {
      if (!_disposed) _storageError = error.code;
    } catch (_) {
      if (!_disposed) _storageError = 'local_drafts_read_failed';
    } finally {
      _restoring = false;
      _notify();
    }
  }

  Future<bool> flush() {
    if (_disposed || !_ready) return Future.value(false);
    if (_storageError == 'local_drafts_conflict') return Future.value(false);
    if (persistence == null) {
      _savedGeneration = _generation;
      return Future.value(true);
    }
    return _saveWork ??= _saveChanges().whenComplete(() => _saveWork = null);
  }

  Future<bool> _saveChanges() async {
    _saving = true;
    _notify();
    try {
      // Retrying a failed save must also clear an error when no data changed.
      do {
        final generation = _generation;
        final snapshot = _closingSnapshot ?? _snapshot();
        _revision = await persistence!.write(
          snapshot,
          expectedRevision: _revision,
        );
        _savedGeneration = generation;
      } while (_savedGeneration != _generation);
      _storageError = null;
      return true;
    } on DraftStorageException catch (error) {
      _storageError = error.code;
      return false;
    } catch (_) {
      _storageError = 'local_drafts_write_failed';
      return false;
    } finally {
      _saving = false;
      _closingSnapshot = null;
      _notify();
    }
  }

  Future<void> rememberSerials(String oldSerial, String newSerial) async {
    if (_disposed || !_ready || _locked || _pending != null) return;
    if (_oldSerial == oldSerial && _newSerial == newSerial) return;
    _oldSerial = oldSerial;
    _newSerial = newSerial;
    _generation++;
    _notify();
    await flush();
  }

  Future<void> capture(Future<PhotoDraft> Function() action) async {
    if (_capturing || isLocked || _saving || _disposed) return;
    _capturing = true;
    _errorCode = null;
    _notify();
    try {
      final photo = await action();
      if (!_disposed) {
        if (_items.any((item) => item.id == photo.id)) {
          throw const CaptureException('capture_failed');
        }
        _items.add(photo);
        _generation++;
        await flush();
      }
    } on CaptureException catch (error) {
      if (!_disposed) _errorCode = error.code;
    } catch (_) {
      if (!_disposed) _errorCode = 'capture_failed';
    } finally {
      _capturing = false;
      _notify();
    }
  }

  Future<void> remove(String id) async {
    if (_disposed || isLocked || _capturing || _saving) return;
    _items.removeWhere((photo) => photo.id == id);
    _generation++;
    _notify();
    await flush();
  }

  void setLocked(bool value) {
    if (_disposed || _locked == value) return;
    _locked = value;
    _notify();
  }

  void beginUpload(UploadBatch batch) {
    _pending = batch;
    _oldSerial = batch.oldSerialNumber;
    _newSerial = batch.newSerialNumber;
    _locked = true;
    _generation++;
    _notify();
  }

  Future<void> rejectUpload() async {
    _pending = null;
    _locked = false;
    _generation++;
    _notify();
    await flush();
  }

  Future<bool> confirmUpload() async {
    if (_disposed) return false;
    if (persistence != null) {
      _saving = true;
      _notify();
      try {
        final revision = await persistence!.write(
          DraftSnapshot(photos: []),
          expectedRevision: _revision,
        );
        if (!_disposed) {
          _apply(StoredDrafts(revision, DraftSnapshot(photos: [])));
        }
      } on DraftStorageException catch (error) {
        _storageError = error.code;
        return false;
      } catch (_) {
        _storageError = 'local_drafts_write_failed';
        return false;
      } finally {
        _saving = false;
        _notify();
      }
    } else {
      _apply(StoredDrafts(0, DraftSnapshot(photos: [])));
      _notify();
    }
    return !_disposed;
  }

  @override
  void dispose() {
    if (_saving) _closingSnapshot = _snapshot();
    _disposed = true;
    _capturing = false;
    _items.clear();
    super.dispose();
  }
}