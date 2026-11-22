import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/control_safe_area.dart';
import '../../l10n/app_localizations.dart';
import '../uploads/upload_controller.dart';
import '../uploads/upload_strings.dart';
import 'capture_error_message.dart';
import 'capture_strings.dart';
import 'camera_framing.dart';
import 'framing_settings_sheet.dart';
import 'photo_draft_store.dart';
import 'photo_review_sheet.dart';

class CaptureView extends StatefulWidget {
  const CaptureView({
    super.key,
    required this.preview,
    required this.drafts,
    required this.onTakePhoto,
    required this.onRetry,
    this.uploads,
    this.loading = false,
    this.cameraReady = true,
    this.cameraError,
  });

  final Widget preview;
  final PhotoDraftStore drafts;
  final UploadController? uploads;
  final VoidCallback onTakePhoto;
  final VoidCallback onRetry;
  final bool loading;
  final bool cameraReady;
  final String? cameraError;

  @override
  State<CaptureView> createState() => _CaptureViewState();
}

class _CaptureViewState extends State<CaptureView> {
  bool _reviewOpen = false;
  bool _framingOpen = false;
  CameraFraming _framing = const CameraFraming();

  Future<void> _editFraming() async {
    if (_framingOpen ||
        _reviewOpen ||
        widget.drafts.isCapturing ||
        widget.uploads?.isUploading == true) {
      return;
    }
    setState(() => _framingOpen = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        barrierColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (sheetContext) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .7,
          ),
          child: FramingSettingsSheet(
            initialValue: _framing,
            onChanged: (value) {
              if (mounted) setState(() => _framing = value);
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _framingOpen = false);
    }
  }

  Future<void> _reviewPhotos({bool promptForSerial = false}) async {
    if (_reviewOpen || _framingOpen || widget.drafts.isCapturing) return;
    setState(() => _reviewOpen = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => PhotoReviewSheet(
          drafts: widget.drafts,
          uploads: widget.uploads,
          promptForSerial: promptForSerial,
        ),
      );
    } finally {
      if (mounted) setState(() => _reviewOpen = false);
    }
  }

  Widget _cameraStatus(AppLocalizations t) {
    if (!widget.loading && widget.cameraError == null) {
      return const SizedBox.shrink();
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.loading) ...[
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
            ],
            Text(
              widget.loading
                  ? t.cameraStarting
                  : captureErrorMessage(t, widget.cameraError!),
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            if (!widget.loading) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const ValueKey('retryCameraButton'),
                onPressed: widget.onRetry,
                child: Text(t.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final labels = CaptureStrings.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.drafts,
        if (widget.uploads != null) widget.uploads!,
      ]),
      builder: (context, _) {
        final drafts = widget.drafts;
        final uploads = widget.uploads;
        final busy = drafts.isCapturing || uploads?.isUploading == true;
        final shutterEnabled =
            widget.cameraReady &&
                !widget.loading &&
                widget.cameraError == null &&
                !busy &&
                !drafts.isLocked &&
                !_reviewOpen &&
                !_framingOpen &&
                uploads?.isLoadingLimits != true;
        final latest = drafts.items.isEmpty ? null : drafts.items.last;

        return PopScope(
          canPop: !busy,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
            ),
            child: Scaffold(
              backgroundColor: Colors.black,
              resizeToAvoidBottomInset: false,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  SizedBox.expand(
                    key: const ValueKey('cameraViewport'),
                    child:
                    widget.cameraReady &&
                        !widget.loading &&
                        widget.cameraError == null
                        ? widget.preview
                        : const ColoredBox(color: Colors.black),
                  ),
                  CameraFramingOverlay(framing: _framing),
                  ControlSafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          key: const ValueKey('cameraControlsScroll'),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: IntrinsicHeight(
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      IconButton.filledTonal(
                                        key: const ValueKey(
                                          'closeCameraButton',
                                        ),
                                        tooltip: labels.close,
                                        onPressed: busy
                                            ? null
                                            : () =>
                                            Navigator.of(context)
                                                .maybePop(),
                                        style: IconButton.styleFrom(
                                          minimumSize: const Size(48, 48),
                                          backgroundColor: Colors.black54,
                                          foregroundColor: Colors.white,
                                          disabledForegroundColor:
                                          Colors.white38,
                                        ),
                                        icon: const Icon(Icons.arrow_back),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          t.captureTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton.filledTonal(
                                        key: const ValueKey(
                                          'cameraFramingButton',
                                        ),
                                        tooltip:
                                        Localizations.localeOf(context)
                                            .languageCode ==
                                            'ro'
                                            ? 'Încadrare cameră'
                                            : 'Camera framing',
                                        onPressed:
                                        busy || _reviewOpen || _framingOpen
                                            ? null
                                            : _editFraming,
                                        style: IconButton.styleFrom(
                                          minimumSize: const Size(48, 48),
                                          backgroundColor: Colors.black54,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.tune),
                                      ),
                                      const SizedBox(width: 8),
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            '${drafts.items.length}',
                                            key: const ValueKey(
                                              'cameraPhotoCount',
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Expanded(child: _cameraStatus(t)),
                                  if (drafts.errorCode != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Text(
                                        captureErrorMessage(
                                          t,
                                          drafts.errorCode!,
                                        ),
                                        key: const ValueKey('captureError'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  if (uploads?.lastReceipt != null &&
                                      drafts.items.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Text(
                                        UploadStrings.of(context).success,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  Row(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: TextButton(
                                          key: const ValueKey(
                                            'reviewPhotosButton',
                                          ),
                                          onPressed: busy || _reviewOpen
                                              ? null
                                              : () => _reviewPhotos(),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.white,
                                            disabledForegroundColor:
                                            Colors.white38,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                BorderRadius.circular(12),
                                                child: SizedBox(
                                                  width: 52,
                                                  height: 52,
                                                  child: latest == null
                                                      ? const ColoredBox(
                                                    color: Colors.black54,
                                                    child: Icon(
                                                      Icons
                                                          .photo_library_outlined,
                                                    ),
                                                  )
                                                      : Image.memory(
                                                    latest.originalBytes,
                                                    fit: BoxFit.cover,
                                                    cacheWidth: 160,
                                                    gaplessPlayback: true,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                labels.photosCount(
                                                  drafts.items.length,
                                                ),
                                                maxLines: 2,
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 84,
                                        height: 84,
                                        child: IconButton.filled(
                                          key: const ValueKey(
                                            'takePhotoButton',
                                          ),
                                          tooltip: drafts.isCapturing
                                              ? t.takingPhoto
                                              : t.takePhoto,
                                          onPressed: shutterEnabled
                                              ? widget.onTakePhoto
                                              : null,
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            foregroundColor: Colors.black,
                                            disabledBackgroundColor:
                                            Colors.white38,
                                            disabledForegroundColor:
                                            Colors.black54,
                                            side: const BorderSide(
                                              color: Colors.white,
                                              width: 3,
                                            ),
                                          ),
                                          icon: drafts.isCapturing
                                              ? const SizedBox(
                                            width: 30,
                                            height: 30,
                                            child:
                                            CircularProgressIndicator(
                                              strokeWidth: 3,
                                              color: Colors.black,
                                            ),
                                          )
                                              : const Icon(
                                            Icons.camera_alt_outlined,
                                            size: 36,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextButton(
                                          key: const ValueKey(
                                            'openUploadButton',
                                          ),
                                          onPressed:
                                          uploads == null ||
                                              drafts.items.isEmpty ||
                                              busy ||
                                              _reviewOpen ||
                                              uploads.isLoadingLimits
                                              ? null
                                              : () => _reviewPhotos(
                                            promptForSerial: true,
                                          ),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.white,
                                            disabledForegroundColor:
                                            Colors.white38,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(
                                                height: 52,
                                                child: Icon(
                                                  Icons.cloud_upload_outlined,
                                                  size: 32,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                labels.upload,
                                                maxLines: 2,
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (drafts.isCapturing)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        t.takingPhoto,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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