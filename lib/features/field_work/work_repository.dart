import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import 'work_models.dart';
import 'work_list_filters.dart';

abstract interface class WorkRepository {
  Future<WorkSettings> settings();
  Future<WorkSettings> updateSettings(WorkSettings current, bool enabled);
  Future<Map<String, dynamic>> list({bool all = false, int page = 1});
  Future<WorkDetails> details(String id);
  Future<List<Map<String, dynamic>>> history(String id);
  Future<Uint8List> image(
      String workId,
      String photoId, {
        bool original = false,
      });
  Future<WorkDetails> save(WorkDraft draft);
}

abstract interface class FilteredWorkRepository implements WorkRepository {
  Future<Map<String, dynamic>> listFiltered({
    bool all = false,
    int page = 1,
    WorkListFilters filters = const WorkListFilters(),
  });
}

class HttpWorkRepository implements FilteredWorkRepository {
  const HttpWorkRepository(this.api);
  final ApiClient api;
  static const root = '/api/field-work';
  @override
  Future<WorkSettings> settings() async =>
      WorkSettings.fromJson(await api.get('$root/settings'));
  @override
  Future<WorkSettings> updateSettings(
      WorkSettings current,
      bool enabled,
      ) async => WorkSettings.fromJson(
    await api.post('$root/settings', {
      'allowQrGeneration': enabled,
      'expectedVersion': current.version,
    }),
  );
  @override
  Future<Map<String, dynamic>> list({bool all = false, int page = 1}) =>
      listFiltered(all: all, page: page);
  @override
  Future<Map<String, dynamic>> listFiltered({
    bool all = false,
    int page = 1,
    WorkListFilters filters = const WorkListFilters(),
  }) => api.get(
    root,
    queryParameters: {'all': all, 'page': page, ...filters.toQueryParameters()},
  );
  @override
  Future<WorkDetails> details(String id) async =>
      WorkDetails.fromJson(await api.get('$root/$id'));
  @override
  Future<List<Map<String, dynamic>>> history(String id) async =>
      ((await api.get('$root/$id/history'))['items'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
  @override
  Future<Uint8List> image(
      String workId,
      String photoId, {
        bool original = false,
      }) => api.getImage(
    '$root/$workId/photos/$photoId/${original ? 'original' : 'stamped'}',
  );
  @override
  Future<WorkDetails> save(WorkDraft draft) async {
    if (draft.pendingChangeId == null) {
      throw StateError('Persist a change ID before sending.');
    }
    final form = FormData();
    form.fields.add(MapEntry('manifest', _manifest(draft)));
    for (final photo in draft.document.photos.where((photo) => photo.isLocal)) {
      form.files.add(
        MapEntry(
          'original_${photo.id}',
          MultipartFile.fromBytes(
            photo.original!,
            filename: '${photo.id}.original',
          ),
        ),
      );
      form.files.add(
        MapEntry(
          'stamped_${photo.id}',
          MultipartFile.fromBytes(photo.stamped!, filename: '${photo.id}.jpg'),
        ),
      );
    }
    return WorkDetails.fromJson(
      await api.postMultipart('$root/${draft.id}/revisions', form),
    );
  }
}

String _manifest(WorkDraft draft) => jsonEncode({
  'changeId': draft.pendingChangeId,
  'expectedVersion': draft.expectedVersion,
  'reason': draft.reason,
  'document': draft.document.toJson(),
});