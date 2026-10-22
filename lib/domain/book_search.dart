import 'speech_segment.dart';

/// Plain-text, offline search over visible speech segments.
/// Returns zero-based segment indices; no content leaves the device.
List<int> findMatchingSegments(
  List<SpeechSegment> segments,
  String query, {
  int maxResults = 100,
}) {
  if (maxResults < 1) throw ArgumentError.value(maxResults, 'maxResults');
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  final result = <int>[];
  for (var index = 0; index < segments.length; index++) {
    if (segments[index].text.toLowerCase().contains(needle)) {
      result.add(index);
      if (result.length >= maxResults) break;
    }
  }
  return result;
}
