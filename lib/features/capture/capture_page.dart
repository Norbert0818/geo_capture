import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../uploads/upload_controller.dart';
import 'camera_preview_cover.dart';
import 'capture_view.dart';
import 'photo_capture_service.dart';
import 'photo_draft.dart';
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
    final camera = _camera;
    return CaptureView(
      drafts: widget.drafts,
      uploads: widget.uploads,
      loading: _loading,
      cameraReady: camera?.value.isInitialized == true,
      cameraError: _cameraError,
      onRetry: _startCamera,
      onTakePhoto: _takePhoto,
      preview: camera == null
          ? const SizedBox.shrink()
          : FullscreenCameraPreview(controller: camera),
    );
  }
}