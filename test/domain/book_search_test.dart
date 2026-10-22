import 'package:ereader/domain/book_search.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const segments = [
    SpeechSegment(0, 12, 'Prima frase.'),
    SpeechSegment(13, 25, 'Another line'),
    SpeechSegment(26, 40, 'Prima ancora.'),
  ];

  test('search ignores case and returns stable segment indices', () {
    expect(findMatchingSegments(segments, 'PRIMA'), [0, 2]);
    expect(findMatchingSegments(segments, 'line'), [1]);
    expect(findMatchingSegments(segments, 'absent'), isEmpty);
  });

  test('search bounds number of results and ignores empty queries', () {
    expect(findMatchingSegments(segments, 'prima', maxResults: 1), [0]);
    expect(findMatchingSegments(segments, '   '), isEmpty);
    expect(() => findMatchingSegments(segments, 'a', maxResults: 0),
        throwsArgumentError);
  });
}
