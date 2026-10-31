import 'offline_voice_audition.dart';

/// In-memory guidance from repeated, user-approved same-phrase tests.
/// No models, files, text, network or user preferences are changed here.
class OfflineVoiceBenchmarkEvidence {
  static const minimumPairs = 3;
  static const maximumPairs = 5;
  final List<OfflineVoiceBenchmarkPair> _pairs = [];
  int? _wholeProcessRssMiB;

  int get samples => _pairs.length;
  int? get wholeProcessRssMiB => _wholeProcessRssMiB;
  List<OfflineVoiceBenchmarkPair> get pairs =>
      List<OfflineVoiceBenchmarkPair>.unmodifiable(_pairs);

  /// Count only completed comparisons that confirm native model reuse
  /// and have two measured, positive synthesis-path durations. Never use
  /// full playback time as a stand-in for neural generation latency.
  bool add(OfflineVoicePreviewReport report) {
    if (report.outcome != OfflineVoicePreviewOutcome.completed) return false;
    final comparison = report.coldWarmComparison;
    if (comparison == null || comparison.reusedNativeModel != true) {
      return false;
    }
    final first = comparison.firstSynthesisPathMs;
    final warm = comparison.secondSynthesisPathMs;
    if (first == null || warm == null || first <= 0 || warm <= 0) {
      return false;
    }
    if (_pairs.length >= maximumPairs) _pairs.removeAt(0);
    _pairs.add(OfflineVoiceBenchmarkPair(first, warm));
    final rss = report.wholeProcessRssMiB;
    if (rss != null && rss > 0) _wholeProcessRssMiB = rss;
    return true;
  }

  bool get enoughEvidence => samples >= minimumPairs;
  int get fasterWarmRuns =>
      _pairs.where((p) => p.firstPathMs > p.warmPathMs).length;
  int? get medianFirstPathMs =>
      _pairs.isEmpty ? null : _median(_pairs.map((p) => p.firstPathMs));
  int? get medianWarmPathMs =>
      _pairs.isEmpty ? null : _median(_pairs.map((p) => p.warmPathMs));
  int? get medianStartupDifferenceMs =>
      _pairs.isEmpty ? null :
      _median(_pairs.map((p) => p.firstPathMs - p.warmPathMs));

  /// Explainable, cautious heuristic only, not a proof or auto-setting:
  /// >=3 valid pairs, >=80% warmer runs faster, median saving >=250ms,
  /// and first-path median at least 1.5x warm-path median.
  bool get manualPrewarmWorthTrying {
    if (!enoughEvidence) return false;
    if (fasterWarmRuns < (samples * 4 + 4) ~/ 5) return false;
    return medianStartupDifferenceMs! >= 250 &&
        medianFirstPathMs! * 2 >= medianWarmPathMs! * 3;
  }

  static int _median(Iterable<int> values) {
    final ordered = values.toList()..sort();
    return ordered[(ordered.length - 1) ~/ 2];
  }
}

class OfflineVoiceBenchmarkPair {
  const OfflineVoiceBenchmarkPair(this.firstPathMs, this.warmPathMs);
  final int firstPathMs;
  final int warmPathMs;
}

String formatOfflineVoiceBenchmarkAdvice(
    OfflineVoiceBenchmarkEvidence evidence) {
  if (!evidence.enoughEvidence) {
    return 'Startup evidence: ${evidence.samples}/'
        '${OfflineVoiceBenchmarkEvidence.minimumPairs} valid, separate '
        'cold/warm comparisons. No preference suggested yet.';
  }
  final delta = evidence.medianStartupDifferenceMs!;
  final difference = delta > 0
      ? '${delta} ms slower'
      : delta < 0 ? '${-delta} ms faster' : 'equal';
  final summary = 'Startup evidence (${evidence.samples} local pairs): '
      'first synthesis path median ${evidence.medianFirstPathMs} ms; '
      'warm median ${evidence.medianWarmPathMs} ms; '
      'first call $difference; warm faster on '
      '${evidence.fasterWarmRuns}/${evidence.samples} runs. ';
  final suggestion = evidence.manualPrewarmWorthTrying
      ? 'Repeated startup overhead observed: manually preparing the '
        'model may help the next preview, but uses RAM for up to '
        '3 minutes. No setting was changed.'
      : 'No consistent large startup overhead established; keep '
        'on-demand Play unless you choose manual Prepare.';
  final ram = evidence.wholeProcessRssMiB == null
      ? ''
      : ' Whole-app RAM snapshot: ${evidence.wholeProcessRssMiB} MiB '
        '(not ONNX-only memory).';
  return '$summary$suggestion$ram '
      'Small device/session sample; OS cache and audible onset not measured.';
}
