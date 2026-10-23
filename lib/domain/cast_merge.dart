import 'voice_cast.dart';

/// A non-destructive preview. No character changes during inspection.
/// The target keeps its stable ID, manual locks and persisted playback refs.
class CastMergePreview {
  const CastMergePreview({
    required this.source,
    required this.target,
    required this.resultingAliases,
    required this.providerConflicts,
    required this.counts,
    required this.snapshotDigest,
  });

  final CastCharacter source;
  final CastCharacter target;
  final List<String> resultingAliases;
  /// Provider conflicts require a user choice: 'source' or 'target'.
  final List<CastMergeVoiceConflict> providerConflicts;
  /// Counts of dependent records which will be retargeted.
  final Map<String, int> counts;
  final String snapshotDigest;
}

class CastMergeVoiceConflict {
  const CastMergeVoiceConflict({
    required this.providerId,
    required this.source,
    required this.target,
  });

  final String providerId;
  final CastVoiceAssignment source;
  final CastVoiceAssignment target;
}

/// Review choices are intentionally required for *each* conflicting voice.
/// Missing decisions make the merge fail; never silently overwrite timbres.
class CastMergeDecision {
  const CastMergeDecision({
    required this.bookId,
    required this.sourceCharacterId,
    required this.targetCharacterId,
    required this.expectedSnapshotDigest,
    required this.providerChoices,
  });

  final String bookId;
  final String sourceCharacterId;
  final String targetCharacterId;
  final String expectedSnapshotDigest;
  /// providerId -> 'source' | 'target'
  final Map<String, String> providerChoices;
}

class CastMergeResult {
  const CastMergeResult({
    required this.mergedName,
    required this.keptCharacterId,
    required this.movedRecordCount,
  });

  final String mergedName;
  final String keptCharacterId;
  final int movedRecordCount;
}
