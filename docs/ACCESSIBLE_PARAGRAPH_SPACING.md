# Accessible paragraph spacing — reader typography increment

Implemented on `feature/m0-flutter-foundation` for ER-028. Source and regression
tests are committed, but Flutter/Dart and Windows/Android runtime validation
have **not** been performed.

## Behavior

- **Reader tools → Reading appearance → Font & layout → Paragraph gaps**:
  a 0.5×–2.5× slider, with 0.1× increments.
- Default **1.0×** preserves previous layout: EPUB standard paragraph bottom
  gap 17 logical pixels (18 for headings), TXT/PDF text-mode segment gap
  6 logical pixels. Chapter-start top gap and in-paragraph line height are
  unchanged.
- Uses the existing per-book visual appearance setting with optional global
  default; saving layout does not change narration, source text, speaker
  assignments, bookmark anchors, or API usage.
- The existing version-1 visual preference JSON remains readable: omitted
  `paragraphSpacingFactor` becomes 1.0. Explicit null, invalid types,
  NaN/infinite values and out-of-range factors are rejected. No SQLite schema
  migration is required.
- PDF **page view** keeps its document-native layout unchanged. The new
  setting affects only its extracted-text reader mode.

## Manual checks on Windows/Android

1. Open an EPUB with consecutive paragraphs, illustrations and headings.
   In **Font & layout**, change paragraph gaps from 1.0× to 2.0×, then 0.5×.
   Confirm only spaces **between blocks** change; text, highlighting, images,
   link taps and TTS speech positions must remain identical.
2. Adjust line height separately to distinguish line spacing from paragraph
   spacing. Check narrow screen, enlarged OS text scaling and night/high
   contrast palettes.
3. Save for the book, close/reopen, and verify the factor is restored; use
   **Set global default** for a second book, then confirm per-book overrides
   keep their own settings.
4. Open TXT and PDF extracted-text reading; verify gap changes there.
   Return to the PDF page viewer: rendered PDF pages must not change.
5. Scroll manually, use search/bookmarks, play/pause and resume from a saved
   source position. Confirm no gap change moves the persisted UTF-16 anchor.
6. Run **manually** with a local Flutter SDK:
   `flutter test test/domain/reading_preferences_test.dart` and
   `flutter test test/features/epub_paragraph_tile_test.dart`,
   then `flutter analyze` and broader tests at final integration.

Regression tests were **authored but not executed**. Do not count this feature
as device-validated or mark the draft PR ready to merge until native verification.
