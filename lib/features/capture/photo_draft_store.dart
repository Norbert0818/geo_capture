import 'package:flutter/foundation.dart';

import 'photo_draft.dart';

class PhotoDraftStore extends ChangeNotifier {
  final _items = <PhotoDraft>[];

  bool _capturing = false;
  bool _locked = false;
  bool _disposed = false;
  String? _errorCode;

  List<PhotoDraft> get items => List.unmodifiable(_items);
  bool get isCapturing => _capturing;
  bool get isLocked => _locked;
  String? get errorCode => _errorCode;

  Future<void> capture(Future<PhotoDraft> Function() action) async {
    if (_capturing || _locked || _disposed) return;

    _capturing = true;
    _errorCode = null;
    notifyListeners();

    try {
      final photo = await action();

      if (!_disposed) _items.add(photo);
    } on CaptureException catch (error) {
      if (!_disposed) _errorCode = error.code;
    } catch (_) {
      if (!_disposed) _errorCode = 'capture_failed';
    } finally {
      if (!_disposed) {
        _capturing = false;
        notifyListeners();
      }
    }
  }

  void remove(String id) {
    if (_disposed || _locked) return;
    _items.removeWhere((photo) => photo.id == id);
    notifyListeners();
  }

  void setLocked(bool value) {
    if (_disposed || _locked == value) return;
    _locked = value;
    notifyListeners();
  }

  void removeUploaded(Set<String> ids) {
    if (_disposed) return;
    _items.removeWhere((photo) => ids.contains(photo.id));
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _capturing = false;
    _items.clear();
    super.dispose();
  }
}