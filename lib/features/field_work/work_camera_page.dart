import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/control_safe_area.dart';
import '../../l10n/app_localizations.dart';
import '../capture/camera_preview_cover.dart';
import '../capture/camera_controls_controller.dart';
import '../capture/camera_controls_view.dart';
import '../capture/camera_framing.dart';
import '../capture/gps_controller.dart';
import '../capture/gps_status_panel.dart';
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
  final _gps = GpsController(GeolocatorGpsSource());
  late final _capture = PhotoCaptureService(
    readLocation: () async => _gps.captureLocation(),
  );
  bool _taking = false;

  CameraController? _camera;
  CameraControlsController? _controls;
  Future<void> _cameraWork = Future<void>.value();
  int _generation = 0;
  bool _loading = true;
  bool _suspended = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gps.addListener(_gpsChanged);
    _startCamera();
  }

  void _startCamera() {
    final generation = ++_generation;
    unawaited(_gps.stop());

    setState(() {
      _loading = true;
      _cameraError = null;
    });

    _cameraWork = _cameraWork.then((_) => _initializeCamera(generation));
  }

  void _gpsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openLocationSettings() async {
    final opened = await GeolocatorGpsSource.openSettings(_gps.status);
    if (mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(GpsStrings.of(context).settingsUnavailable)),
      );
    }
  }

  void _controlsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _releaseCamera() async {
    final camera = _camera;
    final controls = _controls;
    _camera = null;
    _controls = null;
    if (controls != null) {
      controls.removeListener(_controlsChanged);
      await controls.shutdown();
      controls.dispose();
    }
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
    CameraControlsController? candidateControls;
    String? error;

    try {
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
      candidateControls = CameraControlsController(
        DeviceCaptureCameraDriver(candidate),
      );
      await candidateControls.initialize();
      if (!mounted || generation != _generation) return;
      _camera = candidate;
      _controls = candidateControls;
      _controls!.addListener(_controlsChanged);
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
        await candidateControls?.shutdown();
        candidateControls?.dispose();
        await _disposeCamera(candidate);
      }

      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _cameraError = error;
        });
        if (error == null && !_suspended) unawaited(_gps.start());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) &&
        !_suspended) {
      _suspended = true;
      _generation++;
      unawaited(_gps.stop());
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
    if (_taking ||
        _loading ||
        _controls?.busy == true ||
        camera == null ||
        !camera.value.isInitialized ||
        !_gps.canCapture) {
      _gps.refresh();
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
        if (!_gps.canCapture) throw const CaptureException('gps_not_ready');
        return (await camera.takePicture()).readAsBytes();
      });
      if (!mounted || generation != _generation) return;
      await _gps.stop();
      await _releaseCamera();
      if (mounted) Navigator.pop(context, photo);
    } on CaptureException catch (failure) {
      if (mounted && generation == _generation) {
        if (failure.code == 'gps_not_ready') {
          _gps.refresh();
        } else {
          setState(() => _cameraError = failure.code);
        }
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _cameraError = 'capture_failed');
      }
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _gps.removeListener(_gpsChanged);
    _gps.dispose();
    _cameraWork = _cameraWork.then((_) => _releaseCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final ready = !_loading && camera?.value.isInitialized == true;
    final controls = _controls;
    final s = WorkStrings.of(context);
    return PopScope(
      canPop: !_taking,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (ready && controls != null && camera != null)
              ValueListenableBuilder<CameraValue>(
                valueListenable: camera,
                builder: (context, value, _) {
                  final ratio = cameraPreviewAspectRatio(value);
                  if (ratio == null) {
                    return const ColoredBox(color: Colors.black);
                  }
                  return CameraGesturePreview(
                    controls: controls,
                    aspectRatio: ratio,
                    enabled: !_taking,
                    child: FullscreenCameraPreview(controller: camera),
                  );
                },
              ),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_loading || _taking || _cameraError != null)
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_loading || _taking)
                                const CircularProgressIndicator(
                                  color: Colors.white,
                                ),
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
                                          onPressed: _taking
                                              ? null
                                              : _startCamera,
                                          child: Text(
                                            s.text(
                                              'Retry camera',
                                              'Reîncearcă camera',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  GpsCameraControls(
                    gps: _gps,
                    camera: ready ? controls : null,
                    enabled: ready && !_taking,
                    onRefresh: () => unawaited(_gps.start()),
                    onSettings: () => unawaited(_openLocationSettings()),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey('workShutter'),
                    onPressed:
                    ready &&
                        !_taking &&
                        controls?.busy != true &&
                        _gps.canCapture
                        ? _takePhoto
                        : null,
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