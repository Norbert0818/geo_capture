import 'package:flutter/material.dart';

import 'camera_controls_controller.dart';
import 'camera_controls_view.dart';
import 'gps_controller.dart';
import 'gps_quality.dart';

String gpsMeters(double value) =>
    value < 1 ? value.toStringAsPrecision(2) : value.toStringAsFixed(1);

class GpsStrings {
  const GpsStrings(this.romanian);
  final bool romanian;
  static GpsStrings of(BuildContext context) =>
      GpsStrings(Localizations.localeOf(context).languageCode == 'ro');
  String get refresh => romanian ? 'Măsoară din nou' : 'Measure again';
  String get settings => romanian ? 'Setări locație' : 'Location settings';
  String get accuracyHint => romanian
      ? 'Precizia orizontală estimată de telefon, în metri.'
      : 'Estimated horizontal accuracy reported by the phone, in meters.';
  String get settingsUnavailable => romanian
      ? 'Deschide setările dispozitivului pentru permisiunile de locație.'
      : 'Open device settings to change location permissions.';
  String status(GpsController gps) => switch (gps.status) {
    GpsStatus.stopped => romanian ? 'GPS în pauză' : 'GPS paused',
    GpsStatus.searching =>
    romanian ? 'Se caută locația…' : 'Acquiring location…',
    GpsStatus.stabilizing =>
    romanian
        ? 'Măsurători bune: ${gps.goodFixes}/${gps.policy.requiredGoodFixes}'
        : 'Good fixes: ${gps.goodFixes}/${gps.policy.requiredGoodFixes}',
    GpsStatus.ready => romanian ? 'GPS pregătit' : 'GPS ready',
    GpsStatus.weak =>
    romanian
        ? 'Se așteaptă ≤${gpsMeters(gps.policy.targetAccuracyMeters)} m'
        : 'Waiting for ≤${gpsMeters(gps.policy.targetAccuracyMeters)} m',
    GpsStatus.stale =>
    romanian
        ? 'Locație expirată. Măsoară din nou.'
        : 'Location expired. Measure again.',
    GpsStatus.approximate =>
    romanian ? 'Activează locația precisă' : 'Enable precise location',
    GpsStatus.denied =>
    romanian ? 'Permite accesul la locație' : 'Allow location access',
    GpsStatus.disabled =>
    romanian
        ? 'Activează serviciile de locație'
        : 'Turn on location services',
    GpsStatus.unavailable =>
    romanian
        ? 'Locație indisponibilă. Reîncearcă.'
        : 'Location unavailable. Try again.',
  };
}

class GpsStatusPanel extends StatelessWidget {
  const GpsStatusPanel({
    super.key,
    required this.gps,
    required this.onRefresh,
    required this.onSettings,
    this.enabled = true,
  });
  final GpsController gps;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: gps,
    builder: (context, _) {
      final s = GpsStrings.of(context);
      final accuracy = gps.latest?.accuracyMeters;
      final title = accuracy != null && accuracy > 0
          ? 'GPS ±${gpsMeters(accuracy)} m'
          : 'GPS — m';
      final color = switch (gps.status) {
        GpsStatus.ready => Colors.lightGreenAccent,
        GpsStatus.denied ||
        GpsStatus.disabled ||
        GpsStatus.approximate ||
        GpsStatus.unavailable => Colors.orangeAccent,
        _ => Colors.white,
      };
      return SizedBox(
        key: const ValueKey('gpsStatusPanel'),
        height: 80,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  gps.canCapture ? Icons.gps_fixed : Icons.gps_not_fixed,
                  color: color,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: '${s.accuracyHint}\n${s.status(gps)}',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          key: const ValueKey('gpsAccuracy'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          s.status(gps),
                          key: const ValueKey('gpsStatus'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('refreshGps'),
                  tooltip: s.refresh,
                  onPressed: enabled && !gps.starting ? onRefresh : null,
                  color: Colors.white,
                  disabledColor: Colors.white38,
                  icon: const Icon(Icons.my_location),
                ),
                if (gps.needsSettings)
                  IconButton(
                    key: const ValueKey('gpsSettings'),
                    tooltip: s.settings,
                    onPressed: enabled ? onSettings : null,
                    color: Colors.white,
                    disabledColor: Colors.white38,
                    icon: const Icon(Icons.settings_outlined),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class GpsCameraControls extends StatelessWidget {
  const GpsCameraControls({
    super.key,
    required this.gps,
    required this.onRefresh,
    required this.onSettings,
    this.camera,
    this.enabled = true,
  });
  final GpsController gps;
  final CameraControlsController? camera;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final status = GpsStatusPanel(
        gps: gps,
        onRefresh: onRefresh,
        onSettings: onSettings,
        enabled: enabled,
      );
      final controls = camera;
      if (controls == null) return status;
      final panel = CameraControlPanel(controls: controls, enabled: enabled);
      if (constraints.maxWidth >= 600) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: status),
            const SizedBox(width: 8),
            Expanded(child: panel),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [status, const SizedBox(height: 8), panel],
      );
    },
  );
}