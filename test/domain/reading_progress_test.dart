import 'package:ereader/domain/reading_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a source offset produces source-based percentage, never audio time',
      () {
    expect(ReadingSourceProgress.fraction(offset: 250, length: 1000), .25);
    expect(ReadingSourceProgress.percentage(offset: 250, length: 1000), 25);
    expect(ReadingSourceProgress.percentage(offset: 0, length: 1000), 0);
    expect(ReadingSourceProgress.percentage(offset: 1000, length: 1000), 100);
  });

  test('source offset is clamped to the real text boundaries', () {
    expect(ReadingSourceProgress.fraction(offset: -20, length: 100), 0);
    expect(ReadingSourceProgress.fraction(offset: 250, length: 100), 1);
    expect(ReadingSourceProgress.offsetForFraction(
        fraction: -.5, length: 100), 0);
    expect(ReadingSourceProgress.offsetForFraction(
        fraction: 1.5, length: 100), 100);
  });

  test('zero and invalid text lengths cannot divide by zero', () {
    expect(ReadingSourceProgress.percentage(offset: 5, length: 0), 0);
    expect(ReadingSourceProgress.fraction(offset: 5, length: -2), 0);
    expect(ReadingSourceProgress.offsetForFraction(
        fraction: .6, length: 0), 0);
    expect(ReadingSourceProgress.offsetForFraction(
        fraction: .6, length: -5), 0);
  });

  test('fraction to offset rounds safely and keeps full end-of-book', () {
    expect(ReadingSourceProgress.offsetForFraction(
        fraction: .5, length: 101), 51);
    expect(ReadingSourceProgress.offsetForFraction(
        fraction: 1, length: 101), 101);
    expect(ReadingSourceProgress.offsetForFraction(
        fraction: 0, length: 101), 0);
  });

  test('non-finite seek targets are rejected without committing progress',
      () {
    expect(() => ReadingSourceProgress.offsetForFraction(
        fraction: double.nan, length: 100), throwsArgumentError);
    expect(() => ReadingSourceProgress.offsetForFraction(
        fraction: double.infinity, length: 100), throwsArgumentError);
  });
}
