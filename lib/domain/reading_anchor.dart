/// An opaque, versioned source location, stable within a specific file hash.
/// UTF-16 offsets are relative to the named spine item / PDF page.
enum AnchorKind { text, epubSpine, pdfPage }

class ReadingAnchor {
  const ReadingAnchor({
    required this.kind,
    required this.sourceId,
    required this.localOffset,
    this.contextBefore,
    this.contextAfter,
  }) : assert(localOffset >= 0),
       assert((contextBefore == null) == (contextAfter == null));

  final AnchorKind kind;
  final String sourceId;
  final int localOffset;

  /// Version-2 EPUB context fingerprints are truncated SHA-256 digests,
  /// not saved excerpts. Legacy anchors remain version 1.
  final String? contextBefore;
  final String? contextAfter;
  bool get hasContext => contextBefore != null && contextAfter != null;

  Map<String, Object> toJson() => {
    'version': hasContext ? 2 : 1,
    'kind': kind.name,
    'sourceId': sourceId,
    'localOffset': localOffset,
    if (hasContext) 'contextBefore': contextBefore!,
    if (hasContext) 'contextAfter': contextAfter!,
  };

  factory ReadingAnchor.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version != 1 && version != 2) {
      throw const FormatException('Unsupported reading anchor version');
    }
    final id = json['sourceId'];
    final offset = json['localOffset'];
    final kind = json['kind'];
    if (id is! String || id.isEmpty || id.length > 256 ||
        offset is! int || offset < 0 || kind is! String) {
      throw const FormatException('Malformed reading anchor');
    }
    AnchorKind resolvedKind;
    try {
      resolvedKind = AnchorKind.values.byName(kind);
    } on ArgumentError {
      throw const FormatException('Unrecognized reading anchor kind');
    }
    String? before;
    String? after;
    if (version == 2) {
      final rawBefore = json['contextBefore'];
      final rawAfter = json['contextAfter'];
      final digest = RegExp(r'^[0-9a-f]{32}');
      if (resolvedKind != AnchorKind.epubSpine ||
          rawBefore is! String || rawAfter is! String ||
          rawBefore.length != 32 || rawAfter.length != 32 ||
          !digest.hasMatch(rawBefore) || !digest.hasMatch(rawAfter)) {
        throw const FormatException('Malformed EPUB source fingerprint');
      }
      before = rawBefore;
      after = rawAfter;
    }
    return ReadingAnchor(
      kind: resolvedKind,
      sourceId: id,
      localOffset: offset,
      contextBefore: before,
      contextAfter: after,
    );
  }
}
