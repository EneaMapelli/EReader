import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../data/epub_embedded_content.dart';
import '../../domain/book_search.dart';
import 'epub_visual_layout.dart';

/// Display-only, session-local colors. A future reader-preferences screen
/// can persist these without touching source anchors or speech settings.
enum EpubReadingPalette { system, sepia, night }

extension EpubReadingPaletteColors on EpubReadingPalette {
  Color background(BuildContext context) => switch (this) {
    EpubReadingPalette.system =>
        Theme.of(context).scaffoldBackgroundColor,
    EpubReadingPalette.sepia => const Color(0xFFF4ECD9),
    EpubReadingPalette.night => const Color(0xFF17191E),
  };

  Color foreground(BuildContext context) => switch (this) {
    EpubReadingPalette.system => Theme.of(context).colorScheme.onSurface,
    EpubReadingPalette.sepia => const Color(0xFF372B20),
    EpubReadingPalette.night => const Color(0xFFE2E3E7),
  };

  Color highlight(BuildContext context) => switch (this) {
    EpubReadingPalette.system => Theme.of(context).colorScheme.primaryContainer,
    EpubReadingPalette.sepia => const Color(0xFFE7D39B),
    EpubReadingPalette.night => const Color(0xFF3C4968),
  };

  Color highlightForeground(BuildContext context) => switch (this) {
    EpubReadingPalette.system =>
        Theme.of(context).colorScheme.onPrimaryContainer,
    EpubReadingPalette.sepia => const Color(0xFF302414),
    EpubReadingPalette.night => const Color(0xFFF0F3FF),
  };

  Color searchHighlight(BuildContext context) => switch (this) {
    EpubReadingPalette.system =>
        Theme.of(context).colorScheme.tertiaryContainer,
    EpubReadingPalette.sepia => const Color(0xFFF1B66C),
    EpubReadingPalette.night => const Color(0xFF7D5B2C),
  };

  Color searchForeground(BuildContext context) => switch (this) {
    EpubReadingPalette.system =>
        Theme.of(context).colorScheme.onTertiaryContainer,
    EpubReadingPalette.sepia => const Color(0xFF241A12),
    EpubReadingPalette.night => const Color(0xFFFFFFFF),
  };
}

/// Lazy, source-exact EPUB paragraph widget. No HTML WebView, network
/// resources, external CSS or JavaScript are evaluated. Embedded raster
/// assets have already passed manifest, MIME and dimension checks.
/// Individual spoken spans remain tappable without rewriting source text.
class EpubParagraphTile extends StatefulWidget {
  const EpubParagraphTile({
    super.key,
    required this.block,
    required this.activeSegmentIndex,
    this.searchMatch,
    required this.fontSize,
    required this.onSelectSegment,
    this.onOpenLink,
    this.onOpenFootnote,
    this.onOpenAuxiliaryFootnote,
    this.palette = EpubReadingPalette.system,
  });

  final EpubVisualBlock block;
  final int activeSegmentIndex;
  /// Result positions are relative to the original extracted EPUB text.
  final BookSourceMatch? searchMatch;
  final double fontSize;
  final ValueChanged<int> onSelectSegment;
  /// Source offset of a verified internal EPUB fragment (never a URL).
  final ValueChanged<int>? onOpenLink;
  /// A verified note reference requests a non-navigating preview first.
  /// The reader may fall back to ordinary navigation if no preview exists.
  final ValueChanged<int>? onOpenFootnote;
  final ValueChanged<String>? onOpenAuxiliaryFootnote;
  final EpubReadingPalette palette;

  @override
  State<EpubParagraphTile> createState() => _EpubParagraphTileState();
}

class _EpubParagraphTileState extends State<EpubParagraphTile> {
  final Map<int, TapGestureRecognizer> _recognizers = {};
  final Map<(int, bool), TapGestureRecognizer> _linkRecognizers = {};
  final Map<String, TapGestureRecognizer> _auxNoteRecognizers = {};

  TapGestureRecognizer _tap(int index) {
    final recognizer = _recognizers.putIfAbsent(
      index, TapGestureRecognizer.new,
    );
    recognizer.onTap = () => widget.onSelectSegment(index);
    return recognizer;
  }

  TapGestureRecognizer _linkTap(int offset, bool footnote) {
    // Different kinds of link with the same target must never share a
    // mutable callback when widgets are recycled in the lazy EPUB list.
    final recognizer = _linkRecognizers.putIfAbsent(
      (offset, footnote), TapGestureRecognizer.new,
    );
    recognizer.onTap = () {
      if (footnote && widget.onOpenFootnote != null) {
        widget.onOpenFootnote!(offset);
      } else {
        widget.onOpenLink?.call(offset);
      }
    };
    return recognizer;
  }

  TapGestureRecognizer _auxiliaryNoteTap(String key) {
    final recognizer = _auxNoteRecognizers.putIfAbsent(
      key, TapGestureRecognizer.new,
    );
    recognizer.onTap = () => widget.onOpenAuxiliaryFootnote?.call(key);
    return recognizer;
  }

  /// EPUB table preview metadata is already bounded by the extractor.
  /// Compute the rectangular visual width ONCE per table, not once for
  /// every row and cell (which becomes costly for large ragged tables).
  Widget _tablePreview(BuildContext context, EpubTablePreview table) {
    final columns = table.rows.fold<int>(0, (max, row) =>
        row.length > max ? row.length : max);
    final foreground = widget.palette.foreground(context);
    return ExpansionTile(
      title: Text('Table preview (${table.rows.length} rows)'),
      subtitle: const Text('Original spoken text remains above'),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: columns * 160.0,
            child: Table(
              border: TableBorder.all(color: Theme.of(context).dividerColor),
              children: [
                for (final row in table.rows)
                  TableRow(children: [
                    for (var column = 0; column < columns; column++)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          column < row.length ? row[column] : '',
                          style: TextStyle(color: foreground),
                        ),
                      ),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _clearRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
    for (final recognizer in _linkRecognizers.values) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
    for (final recognizer in _auxNoteRecognizers.values) {
      recognizer.dispose();
    }
    _auxNoteRecognizers.clear();
  }

  @override
  void didUpdateWidget(covariant EpubParagraphTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.block, widget.block)) {
      _clearRecognizers();
    }
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  /// Split only the on-screen source run where an exact search hit appears.
  /// Styled/link/TTS text and recognizer identities remain unchanged.
  TextSpan _renderRun(BuildContext context, EpubVisualRun run) {
    final palette = widget.palette;
    final active = run.segmentIndex == widget.activeSegmentIndex;
    final linked = run.linkTargetOffset != null ||
        run.auxiliaryFootnoteKey != null;
    final style = TextStyle(
      fontWeight: run.bold || run.headingLevel > 0
          ? FontWeight.w700 : null,
      fontStyle: run.italic ? FontStyle.italic : null,
      fontSize: run.headingLevel > 0 && !widget.block.heading
          ? widget.fontSize + (7 - run.headingLevel).clamp(1, 6) : null,
      backgroundColor: active ? palette.highlight(context) : null,
      color: active ? palette.highlightForeground(context)
          : linked ? Theme.of(context).colorScheme.primary : null,
      decoration: linked ? TextDecoration.underline : null,
    );
    final recognizer = run.auxiliaryFootnoteKey != null &&
            widget.onOpenAuxiliaryFootnote != null
        ? _auxiliaryNoteTap(run.auxiliaryFootnoteKey!)
        : run.linkTargetOffset != null &&
                (widget.onOpenLink != null ||
                    run.isFootnote && widget.onOpenFootnote != null)
            ? _linkTap(run.linkTargetOffset!, run.isFootnote)
            : run.segmentIndex == null ? null : _tap(run.segmentIndex!);
    final sourceText = run.text;
    TextSpan part(int start, int end, {bool match = false}) {
      final value = sourceText.substring(start - run.start, end - run.start);
      return TextSpan(
        text: value,
        semanticsLabel: run.isFootnote
            ? value + ', footnote link' : null,
        style: match
            ? style.copyWith(
                backgroundColor: palette.searchHighlight(context),
                color: palette.searchForeground(context),
              )
            : style,
        recognizer: recognizer,
      );
    }
    final hit = widget.searchMatch;
    if (hit == null || hit.end <= hit.start ||
        hit.start >= run.end || hit.end <= run.start) {
      return part(run.start, run.end);
    }
    final start = hit.start > run.start ? hit.start : run.start;
    final end = hit.end < run.end ? hit.end : run.end;
    if (start >= end) return part(run.start, run.end);
    return TextSpan(children: [
      if (run.start < start) part(run.start, start),
      part(start, end, match: true),
      if (end < run.end) part(end, run.end),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final heading = widget.block.heading;
    final size = widget.fontSize;
    final style = TextStyle(
      fontFamily: 'serif',
      fontSize: heading ? size + 5 : size,
      height: heading ? 1.35 : 1.75,
      fontWeight: heading ? FontWeight.w600 : FontWeight.w400,
      color: palette.foreground(context),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            8, widget.block.chapterStart ? 24 : 4,
            8, heading ? 18 : 17,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.block.visualOnlySectionTitle != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    header: true,
                    child: Text(
                      widget.block.visualOnlySectionTitle!,
                      style: TextStyle(
                        color: palette.foreground(context),
                        fontSize: size + 4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (widget.block.runs.isNotEmpty)
                Semantics(
                  header: heading,
                  child: Text.rich(
                    TextSpan(children: [
                      for (final run in widget.block.runs)
                        _renderRun(context, run),
                    ]),
                    style: style,
                    textAlign: heading ? TextAlign.start : TextAlign.justify,
                    softWrap: true,
                  ),
                ),
              if (widget.block.visualOnlySectionTitle != null &&
                  widget.block.images.isEmpty)
                Text(
                  'This EPUB section has no selectable text or supported '
                  'embedded illustration. No audio is available here.',
                  style: TextStyle(
                    color: palette.foreground(context),
                    fontSize: size,
                  ),
                ),
              for (final image in widget.block.images)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(
                    image: true,
                    label: image.alt.isEmpty
                        ? 'Embedded book illustration' : image.alt,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 440),
                      child: Image.memory(
                        image.bytes,
                        fit: BoxFit.contain,
                        cacheWidth: 1200,
                        errorBuilder: (context, error, stack) =>
                            const Text('Illustration unavailable'),
                      ),
                    ),
                  ),
                ),
              for (final table in widget.block.tables)
                _tablePreview(context, table),
            ],
          ),
        ),
      ),
    );
  }
}
