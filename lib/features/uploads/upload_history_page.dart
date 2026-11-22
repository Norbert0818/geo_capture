import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import 'history_strings.dart';
import 'serial_numbers_view.dart';
import 'upload_details_page.dart';
import 'upload_history_models.dart';
import 'upload_history_repository.dart';

class UploadHistoryPage extends StatefulWidget {
  const UploadHistoryPage({
    super.key,
    required this.repository,
    this.allUsers = false,
  });

  final UploadHistoryRepository repository;
  final bool allUsers;

  @override
  State<UploadHistoryPage> createState() => _UploadHistoryPageState();
}

class _UploadHistoryPageState extends State<UploadHistoryPage> {
  UploadHistoryResult? _data;
  String? _error;
  bool _loading = true;
  int _requestedPage = 1;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void didUpdateWidget(covariant UploadHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.allUsers != widget.allUsers) {
      _load(1);
    }
  }

  Future<void> _load(int page) async {
    final generation = ++_generation;
    setState(() {
      _requestedPage = page;
      _loading = true;
      _data = null;
      _error = null;
    });
    try {
      final result = await widget.repository.list(
        allUsers: widget.allUsers,
        page: page,
      );
      if (mounted && generation == _generation) setState(() => _data = result);
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

  void _open(UploadHistoryItem item) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            UploadDetailsPage(repository: widget.repository, uploadId: item.id),
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
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.allUsers ? t.allUploads : t.myUploads),
        actions: [
          IconButton(
            key: const ValueKey('refreshHistoryButton'),
            tooltip: t.refresh,
            onPressed: _loading ? null : () => _load(_requestedPage),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: _loading
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(t.loading),
                ],
              ),
            )
                : _error != null
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.error(_error!),
                      key: const ValueKey('historyError'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => _load(_requestedPage),
                      child: Text(t.retry),
                    ),
                  ],
                ),
              ),
            )
                : data == null
                ? const SizedBox.shrink()
                : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.uploads(data.total),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(t.readOnly),
                        Text(t.localTimes),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: data.items.isEmpty
                      ? Center(
                    child: Text(
                      t.empty,
                      key: const ValueKey('historyEmpty'),
                    ),
                  )
                      : RefreshIndicator(
                    onRefresh: () => _load(data.page),
                    child: ListView.builder(
                      key: ValueKey('historyPage:${data.page}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      physics:
                      const AlwaysScrollableScrollPhysics(),
                      itemCount: data.items.length,
                      itemBuilder: (context, index) {
                        final item = data.items[index];
                        return Card(
                          child: InkWell(
                            key: ValueKey('upload:${item.id}'),
                            onTap: () => _open(item),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  SerialNumbersView(summary: item),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${t.uploadedBy}: ${item.uploadedByUsername}',
                                  ),
                                  Text(
                                    '${t.uploadedAt}: ${t.date(item.uploadedAtUtc)}',
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons
                                            .photo_library_outlined,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          t.photos(item.photoCount),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('previousHistoryPage'),
                        tooltip: t.previous,
                        onPressed: data.hasPrevious
                            ? () => _load(data.page - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          t.page(data.page, data.totalPages),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('nextHistoryPage'),
                        tooltip: t.next,
                        onPressed: data.hasNext
                            ? () => _load(data.page + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
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