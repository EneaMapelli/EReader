/// Local, session-only measurements of actual book narration.
/// No text, book title, page, chapter name, voice identity or source
/// offsets are retained. Metrics are kept only in a fixed-size ring.
class NarrationTransitionSample {
  const NarrationTransitionSample({
    required this.isFirstUtterance,
    required this.isChapterTransition,
    required this.speechWallMs,
    this.interSegmentGapMs,
    this.checkpointMs,
    this.neuralSynthesisMs,
    this.decoderHandoffMs,
  });

  final bool isFirstUtterance;
  final bool isChapterTransition;
  /// From native speak() invocation until its Future settles: this
  /// INCLUDES synthesis, playback and native cleanup, not audio-only time.
  final int speechWallMs;
  /// From previous audible speak Future completion until dispatch of this
  /// phrase, including checkpoint, voice selection and deliberate pauses.
  final int? interSegmentGapMs;
  /// Part of that gap spent awaiting the previous completed checkpoint.
  final int? checkpointMs;
  /// Remaining time after the prior checkpoint: next voice selection,
  /// sentence punctuation breath, next onSegmentStarted and skip scanning.
  /// These parts may overlap; never claim this is pure engine latency.
  int? get afterCheckpointGapMs {
    if (interSegmentGapMs == null || checkpointMs == null ||
        checkpointMs! > interSegmentGapMs!) return null;
    return interSegmentGapMs! - checkpointMs!;
  }
  /// Separately reported native synthesis path, only if a new measured
  /// synthesis took place for this utterance.
  final int? neuralSynthesisMs;
  /// Native time from speak entry to decoder handoff, when available.
  /// NOT the first audible sample.
  final int? decoderHandoffMs;

  /// Post-handoff elapsed time, including playback and cleanup, when
  /// handoff timing lies within this utterance's wall time.
  int? get postHandoffMs {
    if (decoderHandoffMs == null ||
        decoderHandoffMs! > speechWallMs) return null;
    return speechWallMs - decoderHandoffMs!;
  }
}

class NarrationTransitionDiagnostics {
  static const maxRecent = 32;
  final List<NarrationTransitionSample> _recent = [];

  List<NarrationTransitionSample> get recent =>
      List<NarrationTransitionSample>.unmodifiable(_recent);
  int get completedUtterances => _recent.length;
  int get observedGaps =>
      _recent.where((sample) => sample.interSegmentGapMs != null).length;
  int get chapterTransitions =>
      _recent.where((sample) => sample.isChapterTransition &&
          sample.interSegmentGapMs != null).length;

  int? get medianGapMs => _median(_recent
      .where((s) => s.interSegmentGapMs != null)
      .map((s) => s.interSegmentGapMs!));
  int? get medianChapterGapMs => _median(_recent
      .where((s) => s.isChapterTransition &&
          s.interSegmentGapMs != null)
      .map((s) => s.interSegmentGapMs!));
  int? get medianRegularGapMs => _median(_recent
      .where((s) => !s.isChapterTransition &&
          s.interSegmentGapMs != null)
      .map((s) => s.interSegmentGapMs!));
  int? get medianCheckpointMs => _median(_recent
      .where((s) => s.checkpointMs != null &&
          s.interSegmentGapMs != null)
      .map((s) => s.checkpointMs!));
  int? get medianAfterCheckpointGapMs => _median(_recent
      .where((s) => s.afterCheckpointGapMs != null)
      .map((s) => s.afterCheckpointGapMs!));
  int? get medianSpeechWallMs =>
      _median(_recent.map((s) => s.speechWallMs));
  int? get medianNeuralSynthesisMs => _median(_recent
      .where((s) => s.neuralSynthesisMs != null)
      .map((s) => s.neuralSynthesisMs!));
  int? get medianPostHandoffMs => _median(_recent
      .where((s) => s.postHandoffMs != null)
      .map((s) => s.postHandoffMs!));

  void record(NarrationTransitionSample sample) {
    if (sample.speechWallMs < 0 ||
        (sample.interSegmentGapMs != null &&
            sample.interSegmentGapMs! < 0) ||
        (sample.checkpointMs != null && sample.checkpointMs! < 0)) {
      throw ArgumentError('Narration timings must not be negative');
    }
    if (_recent.length >= maxRecent) _recent.removeAt(0);
    _recent.add(sample);
  }

  static int? _median(Iterable<int> times) {
    final values = times.toList()..sort();
    if (values.isEmpty) return null;
    return values[(values.length - 1) ~/ 2];
  }
}

/// Evidence-based diagnostic only: never delays a segment, modifies
/// checkpoint durability, enables cloud work or changes speech preferences.
/// A long transition is a >=200ms gap. Three or more recent long gaps
/// AND five measured gaps are required before identifying a likely area.
enum NarrationDelayFocus {
  insufficientEvidence,
  noRepeatedSlowGap,
  checkpoints,
  afterCheckpoint,
  mixed,
}

class NarrationDelayAssessment {
  const NarrationDelayAssessment({
    required this.focus,
    required this.observedGaps,
    required this.longGaps,
    required this.checkpointHeavy,
    required this.afterCheckpointHeavy,
  });

  final NarrationDelayFocus focus;
  final int observedGaps;
  final int longGaps;
  final int checkpointHeavy;
  final int afterCheckpointHeavy;
}

NarrationDelayAssessment assessNarrationDelays(
    NarrationTransitionDiagnostics diagnostics) {
  final pairs = diagnostics.recent.where((sample) =>
      sample.interSegmentGapMs != null &&
      sample.checkpointMs != null &&
      sample.afterCheckpointGapMs != null).toList();
  final slow = pairs.where(
      (sample) => sample.interSegmentGapMs! >= 200).toList();
  // Checkpoint and after-checkpoint partition each single observed gap.
  // Classify as dominated only if >=80% of slow gaps have a >=60% share
  // on one side, with >=100ms absolute contribution in every such gap.
  final checkpointHeavy = slow.where((sample) =>
      sample.checkpointMs! >= 100 &&
      sample.checkpointMs! * 5 >=
          sample.interSegmentGapMs! * 3).length;
  final afterCheckpointHeavy = slow.where((sample) =>
      sample.afterCheckpointGapMs! >= 100 &&
      sample.afterCheckpointGapMs! * 5 >=
          sample.interSegmentGapMs! * 3).length;
  final threshold = (slow.length * 4 + 4) ~/ 5;
  final focus = pairs.length < 5
      ? NarrationDelayFocus.insufficientEvidence
      : slow.length < 3
          ? NarrationDelayFocus.noRepeatedSlowGap
          : checkpointHeavy >= threshold
              ? NarrationDelayFocus.checkpoints
              : afterCheckpointHeavy >= threshold
                  ? NarrationDelayFocus.afterCheckpoint
                  : NarrationDelayFocus.mixed;
  return NarrationDelayAssessment(
    focus: focus, observedGaps: pairs.length,
    longGaps: slow.length, checkpointHeavy: checkpointHeavy,
    afterCheckpointHeavy: afterCheckpointHeavy,
  );
}

String formatNarrationDelayAssessment(
    NarrationTransitionDiagnostics diagnostics) {
  final assessment = assessNarrationDelays(diagnostics);
  final explanation = switch (assessment.focus) {
    NarrationDelayFocus.insufficientEvidence =>
      'Not enough measured transitions to identify a delay source '
      '(at least 5 required).',
    NarrationDelayFocus.noRepeatedSlowGap =>
      'No repeated >=200ms transition delays among recent samples.',
    NarrationDelayFocus.checkpoints =>
      'Repeated delays were mainly in checkpoint acknowledgment; '
      'investigate local persistence before tuning ONNX.',
    NarrationDelayFocus.afterCheckpoint =>
      'Repeated delays were mainly after checkpoint acknowledgment; '
      'inspect voice switching, local preparation and deliberate pauses.',
    NarrationDelayFocus.mixed =>
      'Repeated delays have mixed causes; no dominant stage established.',
  };
  return 'Transition analysis: ${assessment.observedGaps} measured gaps, '
      '${assessment.longGaps} >=200ms; ${assessment.checkpointHeavy} '
      'checkpoint-heavy and ${assessment.afterCheckpointHeavy} '
      'other-work-heavy. $explanation '
      'This is a session-only screening heuristic, not an audio-onset '
      'measurement or automatic performance setting.';
}

String formatNarrationTransitionDiagnostics(
    NarrationTransitionDiagnostics diagnostics) {
  String label(int? value) => value == null ? 'n/a' : '${value} ms';
  return 'Last ${diagnostics.completedUtterances} completed utterances '
      '(max ${NarrationTransitionDiagnostics.maxRecent}): '
      'segment transition median ${label(diagnostics.medianRegularGapMs)} '
      '(${diagnostics.observedGaps - diagnostics.chapterTransitions} samples); '
      'chapter transition median ${label(diagnostics.medianChapterGapMs)} '
      '(${diagnostics.chapterTransitions} samples); '
      'checkpoint wait median ${label(diagnostics.medianCheckpointMs)}; '
      'after-checkpoint gap median '
      '${label(diagnostics.medianAfterCheckpointGapMs)}; '
      'speak() incl. audio median ${label(diagnostics.medianSpeechWallMs)}; '
      'native synthesis path median '
      '${label(diagnostics.medianNeuralSynthesisMs)}; '
      'post-handoff audio/cleanup median '
      '${label(diagnostics.medianPostHandoffMs)}. '
      'Transitions include checkpoint/voice setup/punctuation pauses; '
      'post-handoff is not exact audible playback time. '
      'All statistics are session-only.';
}
