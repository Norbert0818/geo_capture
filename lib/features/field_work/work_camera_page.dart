import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/control_safe_area.dart';
import '../../l10n/app_localizations.dart';
import '../capture/camera_preview_cover.dart';
import '../capture/camera_framing.dart';
import '../capture/capture_error_message.dart';
import '../capture/photo_capture_service.dart';
import '../capture/photo_draft.dart';
import 'work_strings.dart';

class WorkCameraPage extends StatefulWidget {
  const WorkCameraPage({super.key, required this.title});
  final String title;
  @override
  State<WorkCameraPage> createState() => _WorkCameraPageState();
}

class _WorkCameraPageState extends State<WorkCameraPage>
    with WidgetsBindingObserver {
  final _capture = PhotoCaptureService();
  bool _taking = false;

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
    if (_taking || _loading || camera == null || !camera.value.isInitialized) {
      return;
    }
    setState(() => _taking = true);
    try {
      final photo = await _capture.capture(() async {
        if (!mounted ||
            generation != _generation ||
            !identical(camera, _camera)) {
          throw const CaptureException('capture_failed');
        }
        return (await camera.takePicture()).readAsBytes();
      });
      if (!mounted || generation != _generation) return;
      await _releaseCamera();
      if (mounted) Navigator.pop(context, photo);
    } on CaptureException catch (failure) {
      if (mounted) setState(() => _cameraError = failure.code);
    } catch (_) {
      if (mounted) setState(() => _cameraError = 'capture_failed');
    } finally {
      if (mounted) setState(() => _taking = false);
    }
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
    final ready = !_loading && _camera?.value.isInitialized == true;
    final s = WorkStrings.of(context);
    return PopScope(
      canPop: !_taking,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (ready) FullscreenCameraPreview(controller: _camera!),
            const CameraFramingOverlay(framing: CameraFraming()),
            ControlSafeArea(
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _taking
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (_loading || _taking)
                    const CircularProgressIndicator(color: Colors.white),
                  if (_cameraError != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Text(
                              captureErrorMessage(
                                AppLocalizations.of(context)!,
                                _cameraError!,
                              ),
                            ),
                            TextButton(
                              onPressed: _taking ? null : _startCamera,
                              child: Text(
                                s.text('Retry camera', 'Reîncearcă camera'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('workShutter'),
                    onPressed: ready && !_taking ? _takePhoto : null,
                    icon: const Icon(Icons.camera_alt),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(s.text('Take photo', 'Fotografiază')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}