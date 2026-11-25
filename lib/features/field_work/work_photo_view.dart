import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'work_models.dart';
import 'work_repository.dart';
import 'work_strings.dart';

class WorkPhotoImage extends StatefulWidget {
  const WorkPhotoImage({
    super.key,
    required this.photo,
    required this.workId,
    required this.repository,
    this.original = false,
    this.height = 180,
  });
  final WorkPhoto photo;
  final String workId;
  final WorkRepository repository;
  final bool original;
  final double height;
  @override
  State<WorkPhotoImage> createState() => _WorkPhotoImageState();
}

class _WorkPhotoImageState extends State<WorkPhotoImage> {
  late Future<Uint8List> _bytes = _read();
  Future<Uint8List> _read() async =>
      (widget.original ? widget.photo.original : widget.photo.stamped) ??
          await widget.repository.image(
            widget.workId,
            widget.photo.id,
            original: widget.original,
          );
  @override
  void didUpdateWidget(WorkPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.id != widget.photo.id ||
        oldWidget.original != widget.original) {
      _bytes = _read();
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, value) => value.hasData
          ? Image.memory(
        value.data!,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
        const Icon(Icons.broken_image_outlined),
      )
          : value.hasError
          ? IconButton(
        onPressed: () => setState(() => _bytes = _read()),
        icon: const Icon(Icons.refresh),
      )
          : const Center(child: CircularProgressIndicator()),
    ),
  );
}

Future<void> showWorkPhoto(
    BuildContext context,
    WorkPhoto photo,
    String workId,
    WorkRepository repository,
    ) async {
  final s = WorkStrings.of(context);
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.text('Coordinate version', 'Varianta cu coordonate')),
              WorkPhotoImage(
                photo: photo,
                workId: workId,
                repository: repository,
                height: 280,
              ),
              SelectableText(photo.overlayText),
              const Divider(),
              Text(s.text('Original photo', 'Fotografie originală')),
              WorkPhotoImage(
                photo: photo,
                workId: workId,
                repository: repository,
                original: true,
                height: 220,
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(s.text('Close', 'Închide')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}