import 'package:flutter/material.dart';

import 'upload_batch.dart';
import 'upload_controller.dart';
import 'upload_strings.dart';

class UploadPanel extends StatefulWidget {
  const UploadPanel({
    super.key,
    required this.controller,
    this.promptForSerial = false,
  });

  final UploadController controller;
  final bool promptForSerial;

  @override
  State<UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends State<UploadPanel>
    with AutomaticKeepAliveClientMixin<UploadPanel> {
  bool _dialogOpen = false;

  // Keep the one-time serial prompt consumed when this list item scrolls away.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.promptForSerial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _upload();
      });
    }
  }

  Future<void> _upload() async {
    final controller = widget.controller;
    if (_dialogOpen ||
        controller.isUploading ||
        controller.isLoadingLimits ||
        controller.drafts.isCapturing ||
        controller.drafts.items.isEmpty) {
      return;
    }
    final pending = controller.pendingBatch;
    if (pending != null) {
      await controller.submit(pending.serialNumber);
      return;
    }
    setState(() => _dialogOpen = true);
    try {
      if (controller.limits == null) await controller.loadLimits();
      if (!mounted || controller.limits == null) return;
      final serial = await showDialog<String>(
        context: context,
        builder: (_) => SerialNumberDialog(limits: controller.limits!),
      );
      if (mounted && serial != null) await controller.submit(serial);
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = widget.controller;
    final t = UploadStrings.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([controller, controller.drafts]),
      builder: (context, _) {
        final pending = controller.pendingBatch;
        final receipt = controller.lastReceipt;
        final busy = controller.isUploading;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.notice),
                if (controller.limits != null) ...[
                  const SizedBox(height: 8),
                  Text(t.photoLimit(controller.limits!.maxPhotos)),
                ],
                if (controller.isLoadingLimits) ...[
                  const SizedBox(height: 8),
                  Text(t.loading),
                ],
                if (pending != null && !busy) ...[
                  const SizedBox(height: 12),
                  Text(t.retryNotice),
                  Text('${t.serial}: ${pending.serialNumber}'),
                ],
                if (controller.errorCode != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    t.error(controller.errorCode!),
                    key: const ValueKey('uploadError'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (receipt != null) ...[
                  const SizedBox(height: 12),
                  const Icon(Icons.check_circle_outline),
                  Text(
                    t.success,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    t.saved(receipt.photoCount, receipt.serialNumber),
                    key: const ValueKey('uploadSuccess'),
                  ),
                  SelectableText(receipt.id),
                ],
                if (busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: controller.progress),
                  const SizedBox(height: 8),
                  Text(
                    controller.progress == 1
                        ? t.saving
                        : controller.progress == null
                        ? t.uploading
                        : '${t.uploading} ${(controller.progress! * 100).round()}%',
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('uploadPhotosButton'),
                  onPressed:
                  busy ||
                      controller.isLoadingLimits ||
                      controller.drafts.isCapturing ||
                      _dialogOpen ||
                      controller.drafts.items.isEmpty
                      ? null
                      : _upload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    busy
                        ? t.uploading
                        : pending != null
                        ? t.retry
                        : t.upload,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SerialNumberDialog extends StatefulWidget {
  const SerialNumberDialog({super.key, required this.limits});

  final UploadLimits limits;

  @override
  State<SerialNumberDialog> createState() => _SerialNumberDialogState();
}

class _SerialNumberDialogState extends State<SerialNumberDialog> {
  final _form = GlobalKey<FormState>();
  final _serial = TextEditingController();
  bool _submitted = false;

  void _submit() {
    if (_submitted || !_form.currentState!.validate()) return;
    _submitted = true;
    Navigator.of(context).pop(_serial.text.trim());
  }

  @override
  void dispose() {
    _serial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = UploadStrings.of(context);
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: Text(t.serial),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _form,
          child: TextFormField(
            key: const ValueKey('serialNumberField'),
            controller: _serial,
            autofocus: true,
            maxLength: widget.limits.maxSerialNumberLength,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: t.serial),
            validator: (value) => widget.limits.serialError(value ?? '') == null
                ? null
                : t.error('invalid_serial_number'),
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancelUploadButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton(
          key: const ValueKey('confirmUploadButton'),
          onPressed: _submit,
          child: Text(t.upload),
        ),
      ],
    );
  }
}