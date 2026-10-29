/// A local, user-managed collection. A book can be in multiple collections.
class BookCollection {
  const BookCollection({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  static String cleanName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 80 ||
        name.runes.any((unit) => unit < 32 || unit == 127)) {
      throw const FormatException('Collection name must be 1–80 visible characters');
    }
    return name;
  }

  void validate() {
    if (id.isEmpty || id.length > 128 ||
        !RegExp(r'^[a-zA-Z0-9:_-]+$').hasMatch(id) ||
        cleanName(name) != name) {
      throw const FormatException('Invalid book collection');
    }
  }
}
