enum BookFormat { txt, epub, pdf }

extension BookFormatPath on BookFormat {
  String get extension => name;

  static BookFormat? parse(String path) {
    final lower = path.toLowerCase();
    for (final format in BookFormat.values) {
      if (lower.endsWith('.${format.name}')) return format;
    }
    return null;
  }
}

class BookRecord {
  const BookRecord({
    required this.id,
    required this.title,
    required this.localPath,
    required this.format,
    required this.importedAt,
    this.progressOffset = 0,
  });

  final String id;
  final String title;
  final String localPath;
  final BookFormat format;
  final DateTime importedAt;
  /// UTF-16 code-unit offset in the extracted text; prototype only.
  /// Stable per-spine source anchors replace this before M1 completion.
  final int progressOffset;

  BookRecord atOffset(int offset) => BookRecord(
        id: id,
        title: title,
        localPath: localPath,
        format: format,
        importedAt: importedAt,
        progressOffset: offset,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'title': title,
        'localPath': localPath,
        'format': format.name,
        'importedAt': importedAt.toIso8601String(),
        'progressOffset': progressOffset,
      };

  factory BookRecord.fromJson(Map<String, dynamic> json) {
    return BookRecord(
      id: json['id'] as String,
      title: json['title'] as String,
      localPath: json['localPath'] as String,
      format: BookFormat.values.byName(json['format'] as String),
      importedAt: DateTime.parse(json['importedAt'] as String),
      progressOffset: json['progressOffset'] as int? ?? 0,
    );
  }
}
