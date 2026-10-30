import 'book.dart';
import 'book_collection.dart';
import 'library_catalog.dart';
import 'library_search_query.dart';

/// Saved catalog filters, not persisted member IDs. Re-evaluated whenever
/// books are queried; manual collection memberships remain independent.
class SmartBookCollectionRule {
  const SmartBookCollectionRule({
    this.query = '',
    this.format,
    this.favoritesOnly = false,
    this.readingStatus,
    this.activity = LibraryActivityFilter.all,
  });

  final String query;
  final BookFormat? format;
  final bool favoritesOnly;
  final BookReadingStatus? readingStatus;
  final LibraryActivityFilter activity;

  void validate() {
    final parsed = LibrarySearchQuery.parse(query);
    if (!parsed.isValid) throw FormatException(parsed.error!);
    if (query.trim().isEmpty && format == null && !favoritesOnly &&
        readingStatus == null && activity == LibraryActivityFilter.all) {
      throw const FormatException('Select at least one smart collection rule');
    }
  }

  Map<String, Object?> toJson() {
    validate();
    return {
      'query': query.trim(),
      'format': format?.name,
      'favoritesOnly': favoritesOnly,
      'readingStatus': readingStatus?.name,
      'activity': activity.name,
    };
  }

  factory SmartBookCollectionRule.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid smart collection rule');
    }
    const keys = {
      'query', 'format', 'favoritesOnly', 'readingStatus', 'activity',
    };
    if (value.keys.any((key) => !keys.contains(key)) ||
        value['query'] is! String ||
        value['favoritesOnly'] is! bool ||
        value['activity'] is! String) {
      throw const FormatException('Invalid smart collection rule fields');
    }

    T? parseEnum<T extends Enum>(List<T> values, Object? raw) {
      if (raw == null) return null;
      if (raw is! String) {
        throw const FormatException('Invalid smart collection rule value');
      }
      for (final option in values) {
        if (option.name == raw) return option;
      }
      throw const FormatException('Unknown smart collection rule value');
    }

    final activity = parseEnum(
        LibraryActivityFilter.values, value['activity']);
    if (activity == null) {
      throw const FormatException('Missing activity filter');
    }
    final rule = SmartBookCollectionRule(
      query: value['query'] as String,
      format: parseEnum(BookFormat.values, value['format']),
      favoritesOnly: value['favoritesOnly'] as bool,
      readingStatus: parseEnum(
          BookReadingStatus.values, value['readingStatus']),
      activity: activity,
    );
    rule.validate();
    return rule;
  }
}

class SmartBookCollection {
  const SmartBookCollection({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.rule,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final SmartBookCollectionRule rule;

  void validate() {
    if (!RegExp(r'^smart_[a-zA-Z0-9_-]+$').hasMatch(id) ||
        id.length > 128 || BookCollection.cleanName(name) != name) {
      throw const FormatException('Invalid smart collection');
    }
    rule.validate();
  }
}
