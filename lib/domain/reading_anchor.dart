/// An opaque, versioned source location, stable within a specific file hash.
/// UTF-16 offsets are relative to the named spine item / PDF page.
enum AnchorKind { text, epubSpine, pdfPage }

class ReadingAnchor {
  const ReadingAnchor({
    required this.kind,
    required this.sourceId,
    required this.localOffset,
  }) : assert(localOffset >= 0);

  final AnchorKind kind;
  final String sourceId;
  final int localOffset;

  Map<String, Object> toJson() => {
        'version': 1,
        'kind': kind.name,
        'sourceId': sourceId,
        'localOffset': localOffset,
      };

  factory ReadingAnchor.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported reading anchor version');
    }
    final id = json['sourceId'];
    final offset = json['localOffset'];
    if (id is! String || id.isEmpty || offset is! int || offset < 0) {
      throw const FormatException('Malformed reading anchor');
    }
    return ReadingAnchor(
      kind: AnchorKind.values.byName(json['kind'] as String),
      sourceId: id,
      localOffset: offset,
    );
  }
}
