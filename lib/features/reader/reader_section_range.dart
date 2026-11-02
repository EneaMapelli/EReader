import '../../data/epub_navigation.dart';
import '../../domain/reading_progress.dart';
import 'epub_chapter_navigation.dart';

/// Half-open, original UTF-16 source range for a single EPUB directory
/// section. This is not a speech duration, physical page or word count.
class ReaderSectionRange {
  const ReaderSectionRange({required this.start, required this.end});

  final int start;
  final int end;
  int get length => end - start;

  int percentageAt(int absoluteOffset) => ReadingSourceProgress.percentage(
        offset: absoluteOffset - start,
        length: length,
      );

  /// 100% stays INSIDE the selected section, rather than silently
  /// selecting the first character of the following section.
  int offsetAtPercentage(int percent) {
    if (percent < 0 || percent > 100 || length <= 0) {
      throw ArgumentError.value(percent, 'percent', 'Invalid section');
    }
    final local = ReadingSourceProgress.offsetForFraction(
      fraction: percent / 100, length: length,
    );
    return start + local.clamp(0, length - 1).toInt();
  }
}

/// Returns null for empty/invalid/same-start sections, so a percentage
/// never implies precision that the source EPUB cannot provide.
///
/// Publisher TOCs can be out of spine order or hierarchical. The next
/// boundary is the smallest STRICTLY higher source offset across ALL
/// entries, not the next editorial row. Duplicate start offsets are
/// ambiguous and cannot be used to seek within a unique section.
/// When no publisher TOC exists, the OPF spine's exact start/end wins.
ReaderSectionRange? readerSectionRangeForIndex({
  required List<EpubNavigationEntry> authorToc,
  required List<EpubChapter> chapters,
  required int currentIndex,
  required int sourceLength,
}) {
  if (sourceLength <= 0 || currentIndex < 0) return null;
  if (authorToc.isNotEmpty) {
    if (currentIndex >= authorToc.length) return null;
    final start = authorToc[currentIndex].offset;
    if (start < 0 || start >= sourceLength) return null;
    var sameStart = 0;
    var next = sourceLength;
    for (final entry in authorToc) {
      final candidate = entry.offset;
      if (candidate < 0 || candidate > sourceLength) return null;
      if (candidate == start) sameStart++;
      if (candidate > start && candidate < next) next = candidate;
    }
    if (sameStart != 1 || next <= start) return null;
    return ReaderSectionRange(start: start, end: next);
  }
  if (currentIndex >= chapters.length) return null;
  final chapter = chapters[currentIndex];
  if (chapter.start < 0 || chapter.end > sourceLength ||
      chapter.end <= chapter.start) return null;
  // Some EPUBs contain adjacent illustrated-only OPF items with the
  // SAME canonical text offset: no unique 'inside' position exists.
  for (var i = 0; i < chapters.length; i++) {
    if (i != currentIndex && chapters[i].start == chapter.start) {
      return null;
    }
  }
  return ReaderSectionRange(start: chapter.start, end: chapter.end);
}
