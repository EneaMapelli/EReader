import 'reading_anchor.dart';

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
    this.author,
    this.series,
    this.language,
    this.progressOffset = 0,
    this.progressAnchor,
  });

  final String id;
  final String title;
  final String localPath;
  final BookFormat format;
  final DateTime importedAt;
  /// User-editable catalog details, independent of immutable file identity.
  final String? author;
  final String? series;
  final String? language;
  /// Fallback for older libraries; authoritative when no source anchor exists.
  final int progressOffset;
  final ReadingAnchor? progressAnchor;

  BookRecord atOffset(int offset, {ReadingAnchor? anchor}) => BookRecord(
        id: id,
        title: title,
        localPath: localPath,
        format: format,
        importedAt: importedAt,
        author: author,
        series: series,
        language: language,
        progressOffset: offset,
        progressAnchor: anchor,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'title': title,
        'localPath': localPath,
        'format': format.name,
        'importedAt': importedAt.toIso8601String(),
        if (author != null) 'author': author!,
        if (series != null) 'series': series!,
        if (language != null) 'language': language!,
        'progressOffset': progressOffset,
        if (progressAnchor != null) 'progressAnchor': progressAnchor!.toJson(),
      };

  factory BookRecord.fromJson(Map<String, dynamic> json) {
    return BookRecord(
      id: json['id'] as String,
      title: json['title'] as String,
      localPath: json['localPath'] as String,
      format: BookFormat.values.byName(json['format'] as String),
      importedAt: DateTime.parse(json['importedAt'] as String),
      author: json['author'] as String?,
      series: json['series'] as String?,
      language: json['language'] as String?,
      progressOffset: json['progressOffset'] as int? ?? 0,
      progressAnchor: json['progressAnchor'] is Map
          ? ReadingAnchor.fromJson(
              Map<String, dynamic>.from(json['progressAnchor'] as Map))
          : null,
    );
  }
}
