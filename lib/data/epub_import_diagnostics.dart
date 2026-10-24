/// Fixed-category, bounded import diagnostics. Never persist or display
/// arbitrary XHTML, URLs, filesystem paths or attacker-controlled strings.
enum EpubDiagnosticCode {
  emptySpineItem,
  missingAuthorToc,
  unreadableAuthorToc,
  unresolvedInternalLink,
  unavailableFootnote,
  rejectedImage,
  droppedInlineStyle,
}

class EpubImportDiagnostic {
  const EpubImportDiagnostic(this.code, this.occurrences);
  final EpubDiagnosticCode code;
  final int occurrences;

  String get description {
    switch (code) {
      case EpubDiagnosticCode.emptySpineItem:
        return 'Spine item without readable text was skipped';
      case EpubDiagnosticCode.missingAuthorToc:
        return 'Publisher table of contents unavailable; spine index used';
      case EpubDiagnosticCode.unreadableAuthorToc:
        return 'Publisher navigation invalid or without readable targets';
      case EpubDiagnosticCode.unresolvedInternalLink:
        return 'Internal link was excluded: missing or unsafe target';
      case EpubDiagnosticCode.unavailableFootnote:
        return 'Referenced footnote could not be previewed';
      case EpubDiagnosticCode.rejectedImage:
        return 'Embedded image could not be displayed safely';
      case EpubDiagnosticCode.droppedInlineStyle:
        return 'Unsupported inline formatting shown as plain text';
    }
  }
}

/// Fixed-size aggregation: arbitrary EPUB data cannot grow the diagnostic
/// list or leak URLs, author text or private local paths into UI/logs.
class EpubImportDiagnostics {
  final Map<EpubDiagnosticCode, int> _counts = {};

  void record(EpubDiagnosticCode code) {
    final previous = _counts[code] ?? 0;
    if (previous < 9999) _counts[code] = previous + 1;
  }

  List<EpubImportDiagnostic> get items => List.unmodifiable([
    for (final code in EpubDiagnosticCode.values)
      if (_counts.containsKey(code))
        EpubImportDiagnostic(code, _counts[code]!),
  ]);
}
