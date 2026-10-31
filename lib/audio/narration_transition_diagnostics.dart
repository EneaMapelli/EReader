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

String formatNarrationTransitionDiagnostics(
    NarrationTransitionDiagnostics diagnostics) {
  String label(int? value) => value == null ? 'n/a' : '${value} ms';
  return 'Last ${diagnostics.completedUtterances} completed utterances '
      '(max ${NarrationTransitionDiagnostics.maxRecent}): '
      'sentence transition median ${label(diagnostics.medianRegularGapMs)} '
      '(${diagnostics.observedGaps - diagnostics.chapterTransitions} samples); '
      'chapter transition median ${label(diagnostics.medianChapterGapMs)} '
      '(${diagnostics.chapterTransitions} samples); '
      'speak() incl. audio median ${label(diagnostics.medianSpeechWallMs)}; '
      'native synthesis path median '
      '${label(diagnostics.medianNeuralSynthesisMs)}; '
      'post-handoff audio/cleanup median '
      '${label(diagnostics.medianPostHandoffMs)}. '
      'Transitions include checkpoint/voice setup/punctuation pauses; '
      'post-handoff is not exact audible playback time. '
      'All statistics are session-only.';
}
