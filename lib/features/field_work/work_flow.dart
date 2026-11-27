import 'work_models.dart';

typedef WorkFlowStep = ({String key, bool identity, bool newPole});

List<WorkFlowStep> workFlow(WorkKind kind) => switch (kind) {
  WorkKind.replacement => const [
    (key: 'oldIdentity', identity: true, newPole: false),
    (key: 'old', identity: false, newPole: false),
    (key: 'newIdentity', identity: true, newPole: true),
    (key: 'new', identity: false, newPole: false),
  ],
  WorkKind.repair => const [
    (key: 'before', identity: false, newPole: false),
    (key: 'identity', identity: true, newPole: false),
    (key: 'after', identity: false, newPole: false),
  ],
  WorkKind.removal => const [
    (key: 'identity', identity: true, newPole: false),
    (key: 'pole', identity: false, newPole: false),
  ],
  WorkKind.pit => const [(key: 'pit', identity: false, newPole: false)],
};

bool workStepComplete(WorkDocument document, int index) {
  final steps = workFlow(document.kind);
  if (index < 0 || index >= steps.length) return false;
  final step = steps[index];
  if (step.identity) {
    final identity = step.newPole ? document.newPole : document.oldPole;
    return identity?.valid == true &&
        (!step.newPole || identity!.ntetCode.trim().isNotEmpty);
  }
  final photos = document.photos
      .where((photo) => photo.role == step.key)
      .toList();
  return photos.isNotEmpty &&
      photos.every(
            (photo) =>
        photo.locality.trim().isNotEmpty &&
            photo.county.trim().isNotEmpty &&
            (photo.role != 'old' || photo.serialVisible),
      );
}

int? firstInvalidWorkStep(WorkDraft draft) {
  final steps = workFlow(draft.document.kind);
  for (var index = 0; index < steps.length; index++) {
    if (!workStepComplete(draft.document, index)) return index;
  }
  if (!draft.document.complete ||
      (draft.expectedVersion != null && draft.reason.trim().length < 3)) {
    return steps.length - 1;
  }
  return null;
}