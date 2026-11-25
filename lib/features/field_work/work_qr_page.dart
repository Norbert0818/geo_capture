import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/widgets/control_safe_area.dart';
import 'work_models.dart';
import 'work_strings.dart';

Future<Uint8List> renderWorkQr(String data) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
  canvas.translate(64, 64);
  QrPainter(
    data: data,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    eyeStyle: const QrEyeStyle(color: Colors.black),
    dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
    gapless: true,
  ).paint(canvas, const Size(896, 896));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1024, 1024);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (bytes == null) throw StateError('QR export failed');
  return bytes.buffer.asUint8List();
}

class WorkQrScanPage extends StatefulWidget {
  const WorkQrScanPage({super.key});
  @override
  State<WorkQrScanPage> createState() => _WorkQrScanPageState();
}

class _WorkQrScanPageState extends State<WorkQrScanPage>
    with WidgetsBindingObserver {
  final _scanner = MobileScannerController(
    formats: [BarcodeFormat.qrCode, BarcodeFormat.dataMatrix],
  );
  final Set<String> _values = {};
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setRunning(state == AppLifecycleState.resumed && !_closing);
  }

  Future<void> _setRunning(bool running) async {
    try {
      if (running) {
        await _scanner.start();
      } else {
        await _scanner.stop();
      }
    } catch (_) {
      /* Permission dialogs and disposal can overlap lifecycle changes. */
    }
  }

  Future<void> _select(String value) async {
    if (_closing) return;
    _closing = true;
    await _setRunning(false);
    if (mounted) Navigator.pop(context, value);
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('Scan pole code', 'Scanează codul stâlpului')),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: (capture) {
              if (_closing || !mounted) return;
              final values = capture.barcodes
                  .map((b) => b.rawValue)
                  .whereType<String>()
                  .where((value) => value.isNotEmpty && value.length <= 4096);
              setState(() => _values.addAll(values));
            },
          ),
          ControlSafeArea(
            child: Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      s.text(
                        'Point at a QR or Data Matrix code. Select the correct result below; nothing opens automatically.',
                        'Îndreaptă camera spre un cod QR sau Data Matrix. Alege rezultatul corect; nu se deschide nimic automat.',
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (_values.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: Card(
                      child: ListView(
                        shrinkWrap: true,
                        children: _values
                            .take(10)
                            .map(
                              (value) => ListTile(
                            title: Text(
                              value,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.check),
                            onTap: () => _select(value),
                          ),
                        )
                            .toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WorkQrCard extends StatelessWidget {
  const WorkQrCard({super.key, required this.pole});
  final PoleIdentity pole;
  Future<void> _export(BuildContext context) async {
    final data = pole.rawCode;
    if (data == null || data.isEmpty) return;
    final bytes = await renderWorkQr(data);
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final serial = pole.serialNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png')],
        fileNameOverrides: [
          'pole-${serial.length > 100 ? serial.substring(0, 100) : serial}.png',
        ],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = pole.rawCode;
    if (data == null || data.isEmpty || pole.source == 'manual') {
      return const SizedBox.shrink();
    }
    final s = WorkStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            QrImageView(
              data: data,
              version: QrVersions.auto,
              size: 220,
              padding: const EdgeInsets.all(20),
              backgroundColor: Colors.white,
            ),
            SelectableText(
              '${pole.ntetCode}\n${pole.serialNumber}',
              textAlign: TextAlign.center,
            ),
            TextButton.icon(
              onPressed: () async {
                try {
                  await _export(context);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          s.text('QR export failed.', 'Exportul QR a eșuat.'),
                        ),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.share),
              label: Text(s.text('Export QR image', 'Exportă imaginea QR')),
            ),
          ],
        ),
      ),
    );
  }
}