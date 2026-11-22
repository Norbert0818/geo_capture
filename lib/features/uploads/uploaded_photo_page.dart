import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import 'history_strings.dart';
import 'upload_history_models.dart';
import 'upload_history_repository.dart';

class UploadedPhotoPage extends StatefulWidget {
  const UploadedPhotoPage({
    super.key,
    required this.repository,
    required this.uploadId,
    required this.photo,
    this.initialOriginal = false,
  });

  final UploadHistoryRepository repository;
  final String uploadId;
  final StoredPhoto photo;
  final bool initialOriginal;

  @override
  State<UploadedPhotoPage> createState() => _UploadedPhotoPageState();
}

class _UploadedPhotoPageState extends State<UploadedPhotoPage> {
  late bool _original = widget.initialOriginal;
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  CancelToken? _request;

  @override
  void initState() {
    super.initState();
    _load(_original);
  }

  @override
  void didUpdateWidget(covariant UploadedPhotoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.id != widget.photo.id ||
        oldWidget.uploadId != widget.uploadId ||
        oldWidget.repository != widget.repository) {
      _load(widget.initialOriginal);
    }
  }

  Future<void> _load(bool original) async {
    final generation = ++_generation;
    _request?.cancel('Image variant changed');
    final request = CancelToken();
    _request = request;
    setState(() {
      _original = original;
      _loading = true;
      _error = null;
      _bytes = null;
    });
    try {
      final result = await widget.repository.image(
        widget.uploadId,
        widget.photo.id,
        original: original,
        cancelToken: request,
      );
      if (mounted && generation == _generation) setState(() => _bytes = result);
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

  @override
  void dispose() {
    _generation++;
    _request?.cancel('Image viewer closed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HistoryStrings.of(context);
    final bytes = _bytes;
    return Scaffold(
      appBar: AppBar(title: Text(t.photo(widget.photo.position + 1))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('viewStampedChip'),
                        label: Text(t.stamped),
                        selected: !_original,
                        onSelected: (_) {
                          if (_original) _load(false);
                        },
                      ),
                      ChoiceChip(
                        key: const ValueKey('viewOriginalChip'),
                        label: Text(t.original),
                        selected: _original,
                        onSelected: (_) {
                          if (!_original) _load(true);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    widget.photo.coordinatesText,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
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
                              key: const ValueKey('savedPhotoError'),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => _load(_original),
                              child: Text(t.retry),
                            ),
                          ],
                        ),
                      ),
                    )
                  : bytes == null
                  ? const SizedBox.shrink()
                  : ColoredBox(
                      color: Colors.black,
                      child: InteractiveViewer(
                        key: ValueKey('savedPhotoViewer:$_original'),
                        minScale: 1,
                        maxScale: 8,
                        child: SizedBox.expand(
                          child: Image.memory(
                            bytes,
                            key: const ValueKey('savedPhotoImage'),
                            semanticLabel: _original ? t.original : t.stamped,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stack) => Center(
                              child: Text(
                                t.error('service_unavailable'),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
