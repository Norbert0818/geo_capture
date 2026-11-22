import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import 'history_strings.dart';
import 'upload_history_models.dart';
import 'upload_history_repository.dart';
import 'uploaded_photo_page.dart';

class UploadDetailsPage extends StatefulWidget {
  const UploadDetailsPage({
    super.key,
    required this.repository,
    required this.uploadId,
  });

  final UploadHistoryRepository repository;
  final String uploadId;

  @override
  State<UploadDetailsPage> createState() => _UploadDetailsPageState();
}

class _UploadDetailsPageState extends State<UploadDetailsPage> {
  StoredUpload? _upload;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UploadDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uploadId != widget.uploadId ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _upload = null;
    });
    try {
      final result = await widget.repository.details(widget.uploadId);
      if (mounted && generation == _generation) {
        setState(() => _upload = result);
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.code);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'service_unavailable');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _open(StoredPhoto photo, bool original) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UploadedPhotoPage(
          repository: widget.repository,
          uploadId: widget.uploadId,
          photo: photo,
          initialOriginal: original,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HistoryStrings.of(context);
    final upload = _upload;
    return Scaffold(
      appBar: AppBar(title: Text(t.details)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.error(_error!),
                            key: const ValueKey('detailsError'),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _load, child: Text(t.retry)),
                        ],
                      ),
                    ),
                  )
                : upload == null
                ? const SizedBox.shrink()
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        upload.summary.serialNumber,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${t.uploadedBy}: ${upload.summary.uploadedByUsername}',
                      ),
                      Text(
                        '${t.uploadedAt}: ${t.date(upload.summary.uploadedAtUtc)}',
                      ),
                      Text(t.photos(upload.photos.length)),
                      const SizedBox(height: 12),
                      Text(t.readOnly),
                      Text(t.localTimes),
                      const SizedBox(height: 20),
                      for (final photo in upload.photos)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.photo(photo.position + 1),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  photo.coordinatesText,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${t.accuracy}: ${photo.accuracyMeters.toStringAsFixed(1)} m',
                                ),
                                Text(
                                  '${t.capturedAt}: ${t.date(photo.capturedAtUtc)}',
                                ),
                                Text(
                                  '${t.measuredAt}: ${t.date(photo.locationMeasuredAtUtc)}',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${t.original}: ${photo.originalWidth} × ${photo.originalHeight} · ${t.size(photo.originalByteLength)}',
                                ),
                                Text(
                                  '${t.stamped}: ${photo.stampedWidth} × ${photo.stampedHeight} · ${t.size(photo.stampedByteLength)}',
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.tonalIcon(
                                      key: ValueKey('stamped:${photo.id}'),
                                      onPressed: () => _open(photo, false),
                                      icon: const Icon(
                                        Icons.location_on_outlined,
                                      ),
                                      label: Text(t.stamped),
                                    ),
                                    OutlinedButton.icon(
                                      key: ValueKey('original:${photo.id}'),
                                      onPressed: () => _open(photo, true),
                                      icon: const Icon(Icons.image_outlined),
                                      label: Text(t.original),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
