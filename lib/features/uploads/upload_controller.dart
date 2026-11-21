import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../capture/photo_draft_store.dart';
import 'upload_batch.dart';
import 'upload_repository.dart';

class UploadController extends ChangeNotifier {
  UploadController({required this.drafts, required this.repository});

  final PhotoDraftStore drafts;
  final UploadRepository repository;

  UploadLimits? limits;
  UploadBatch? pendingBatch;
  UploadReceipt? lastReceipt;
  String? errorCode;
  bool isUploading = false;
  bool isLoadingLimits = false;
  double? progress;
  bool _disposed = false;

  Future<void> loadLimits() async {
    if (_disposed || isLoadingLimits || isUploading) return;
    isLoadingLimits = true;
    errorCode = null;
    notifyListeners();
    try {
      final result = await repository.getLimits();
      if (!_disposed) limits = result;
    } on ApiException catch (error) {
      if (!_disposed) errorCode = error.code;
    } catch (_) {
      if (!_disposed) errorCode = 'service_unavailable';
    } finally {
      if (!_disposed) {
        isLoadingLimits = false;
        notifyListeners();
      }
    }
  }

  Future<void> submit(String serialNumber) async {
    if (_disposed || isUploading || isLoadingLimits || drafts.isCapturing) {
      return;
    }
    errorCode = null;
    lastReceipt = null;
    try {
      if (pendingBatch == null) {
        final currentLimits = limits;
        if (currentLimits == null) {
          throw const ApiException('service_unavailable');
        }
        pendingBatch = UploadBatch.create(
          serialNumber: serialNumber,
          photos: drafts.items,
          limits: currentLimits,
        );
      }
    } on ApiException catch (error) {
      errorCode = error.code;
      notifyListeners();
      return;
    }

    final batch = pendingBatch!;
    isUploading = true;
    progress = null;
    drafts.setLocked(true);
    notifyListeners();

    try {
      final receipt = await repository.upload(
        batch,
        onProgress: (sent, total) {
          if (_disposed) return;
          progress = total > 0 ? (sent / total).clamp(0.0, 1.0) : null;
          notifyListeners();
        },
      );
      if (_disposed) return;
      if (!receipt.confirms(batch)) {
        throw const ApiException('service_unavailable');
      }
      // A progress of 100% only means sent; remove drafts after server confirmation.
      drafts.removeUploaded(batch.photos.map((photo) => photo.id).toSet());
      pendingBatch = null;
      lastReceipt = receipt;
    } on ApiException catch (error) {
      if (_disposed) return;
      errorCode = error.code;
      // These responses reject the batch before saving, so editing is safe.
      if ({400, 413, 415}.contains(error.statusCode)) pendingBatch = null;
    } catch (_) {
      if (!_disposed) errorCode = 'service_unavailable';
    } finally {
      if (!_disposed) {
        isUploading = false;
        drafts.setLocked(pendingBatch != null);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    pendingBatch = null;
    super.dispose();
  }
}