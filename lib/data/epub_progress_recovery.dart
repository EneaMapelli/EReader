import '../domain/reading_anchor.dart';
import '../domain/epub_anchor_context.dart';
import 'book_decoder.dart';

enum EpubProgressRecoveryStatus {
  exact,
  relocated,
  legacyUnverified,
  needsReview,
}

/// A definite source position is used only when the original source anchor
/// still verifies or its 2-sided fingerprint has exactly one match within
/// the same OPF spine item. Never search other books or other chapters.
class EpubProgressRecovery {
  const EpubProgressRecovery(this.offset, this.status);
  final int offset;
  final EpubProgressRecoveryStatus status;

  bool get needsReview => status == EpubProgressRecoveryStatus.needsReview;
  bool get shouldPersist =>
      status == EpubProgressRecoveryStatus.relocated;
}

EpubProgressRecovery resolveEpubReadingProgress(
  DocumentContent document, {
  required ReadingAnchor? anchor,
  required int legacyOffset,
}) {
  final ranges = document.epubSpineRanges;
  final source = document.text;
  if (ranges.isEmpty || source.isEmpty) {
    throw const FormatException('No EPUB reading source to recover');
  }
  if (anchor == null) {
    // A database created before source anchors has no context evidence.
    // Keep its original offset for compatibility, but label it unverified.
    return EpubProgressRecovery(
      legacyOffset.clamp(0, source.length - 1).toInt(),
      EpubProgressRecoveryStatus.legacyUnverified,
    );
  }
  if (anchor.kind != AnchorKind.epubSpine) {
    return const EpubProgressRecovery(
        0, EpubProgressRecoveryStatus.needsReview);
  }
  for (final range in ranges) {
    if (range.idref != anchor.sourceId) continue;
    final absolute = range.start + anchor.localOffset;
    if (!anchor.hasContext) {
      final old = document.offsetOf(anchor);
      if (old != null) {
        return EpubProgressRecovery(
            old, EpubProgressRecoveryStatus.legacyUnverified);
      }
      // Keep the last *known chapter* but do not silently clamp to some
      // different word when its old local offset no longer exists.
      return EpubProgressRecovery(
          range.start, EpubProgressRecoveryStatus.needsReview);
    }
    if (absolute >= range.start && absolute <= range.end &&
        EpubAnchorContext.matches(
            source, range.start, range.end, absolute, anchor)) {
      return EpubProgressRecovery(
          absolute, EpubProgressRecoveryStatus.exact);
    }
    final moved = EpubAnchorContext.relocate(
        source, range.start, range.end, anchor);
    if (moved != null) {
      return EpubProgressRecovery(
          moved, EpubProgressRecoveryStatus.relocated);
    }
    // Unverifiable or repeated text never permits a best-guess seek.
    return EpubProgressRecovery(
        range.start, EpubProgressRecoveryStatus.needsReview);
  }
  // The original spine item no longer exists: even the absolute offset
  // may now point to another chapter. Start safely at the beginning.
  return const EpubProgressRecovery(
      0, EpubProgressRecoveryStatus.needsReview);
}
