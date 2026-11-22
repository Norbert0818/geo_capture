import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../uploads/upload_controller.dart';
import '../uploads/upload_panel.dart';
import 'capture_error_message.dart';
import 'photo_capture_service.dart';
import 'photo_draft.dart';
import 'photo_draft_card.dart';
import 'photo_draft_store.dart';
import 'photo_preparation_service.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({super.key, required this.drafts, this.uploads});

  final PhotoDraftStore drafts;
  final UploadController? uploads;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> with WidgetsBindingObserver {
  final _capture = PhotoPreparationService();

  CameraController? _camera;
  Future<void> _cameraWork = Future<void>.value();
  int _generation = 0;
  bool _loading = true;
  bool _suspended = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  void _startCamera() {
    final generation = ++_generation;

    setState(() {
      _loading = true;
      _cameraError = null;
    });

    _cameraWork = _cameraWork.then((_) => _initializeCamera(generation));
  }

  Future<void> _releaseCamera() async {
    final camera = _camera;
    _camera = null;
    await _disposeCamera(camera);
  }

  Future<void> _disposeCamera(CameraController? camera) async {
    try {
      await camera?.dispose();
    } catch (_) {
      // A disconnected camera may already have been released.
    }
  }

  Future<void> _initializeCamera(int generation) async {
    await _releaseCamera();

    if (!mounted || generation != _generation) return;

    CameraController? candidate;
    String? error;

    try {
      await PhotoCaptureService.prepareLocation();
      if (!mounted || generation != _generation) return;

      final cameras = await availableCameras();

      if (!mounted || generation != _generation) return;

      if (cameras.isEmpty) {
        throw const CaptureException('camera_unavailable');
      }

      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      candidate = CameraController(
        description,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );

      await candidate.initialize();

      if (!mounted || generation != _generation) return;

      _camera = candidate;
    } on CaptureException catch (failure) {
      error = failure.code;
    } on CameraException catch (failure) {
      error =
          failure.code.startsWith('CameraAccess') ||
              failure.code == 'permissionDenied'
          ? 'camera_denied'
          : 'camera_unavailable';
    } catch (_) {
      error = 'camera_unavailable';
    } finally {
      if (!identical(candidate, _camera)) {
        await _disposeCamera(candidate);
      }

      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _cameraError = error;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !_suspended &&
        _camera?.value.isInitialized == true) {
      _suspended = true;
      _generation++;
      setState(() => _loading = true);
      _cameraWork = _cameraWork.then((_) => _releaseCamera());
    } else if (state == AppLifecycleState.resumed && _suspended) {
      _suspended = false;
      _startCamera();
    }
  }

  Future<void> _takePhoto() async {
    final camera = _camera;
    final generation = _generation;

    if (_loading || camera == null || !camera.value.isInitialized) return;

    await widget.drafts.capture(
      () => _capture.capture(() async {
        if (!mounted ||
            generation != _generation ||
            !identical(camera, _camera)) {
          throw const CaptureException('capture_failed');
        }

        final file = await camera.takePicture();
        return file.readAsBytes();
      }),
    );
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _cameraWork = _cameraWork.then((_) => _releaseCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.drafts,
        if (widget.uploads != null) widget.uploads!,
      ]),
      builder: (context, _) {
        final drafts = widget.drafts;

        return PopScope(
          canPop: !drafts.isCapturing && widget.uploads?.isUploading != true,
          child: Scaffold(
            appBar: AppBar(title: Text(t.captureTitle)),
            body: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SizedBox(
                      height: 320,
                      child: _loading
                          ? Center(child: Text(t.cameraStarting))
                          : _cameraError != null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  captureErrorMessage(t, _cameraError!),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton(
                                  onPressed: _startCamera,
                                  child: Text(t.retry),
                                ),
                              ],
                            )
                          : ColoredBox(
                              color: Colors.black,
                              child: Center(child: CameraPreview(_camera!)),
                            ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('takePhotoButton'),
                      onPressed:
                          _loading ||
                              _camera == null ||
                              drafts.isCapturing ||
                              drafts.isLocked ||
                              widget.uploads?.isLoadingLimits == true
                          ? null
                          : _takePhoto,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        drafts.isCapturing ? t.takingPhoto : t.takePhoto,
                      ),
                    ),
                    if (drafts.errorCode != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        captureErrorMessage(t, drafts.errorCode!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(t.draftNotice),
                    if (widget.uploads != null) ...[
                      const SizedBox(height: 16),
                      UploadPanel(controller: widget.uploads!),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      '${t.pendingPhotos} (${drafts.items.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (drafts.items.isEmpty) Text(t.noPhotosYet),
                    for (final photo in drafts.items)
                      PhotoDraftCard(
                        key: ValueKey(photo.id),
                        photo: photo,
                        onRemove: drafts.isLocked
                            ? null
                            : () => drafts.remove(photo.id),
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
