import '../domain/book.dart';
import 'batch_book_import.dart';

/// Pure validation shared by tests and the Windows native drop receiver.
/// Rejects directories, URLs and non-book extensions before opening streams.
///
/// Only the basename reaches importer/UI, never a source filesystem path.
class DesktopBookDropSelection {
  const DesktopBookDropSelection({
    required this.accepted,
    required this.unsupportedNames,
  });

  final List<BatchPickedBook> accepted;
  final List<String> unsupportedNames;
  int get rejectedCount => unsupportedNames.length;
}

String safeDroppedBookName(String input) {
  final base = input.replaceAll('\\', '/').split('/').last
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  if (base.isEmpty || base == '.' || base == '..') return '';
  return base.length > 240 ? '' : base;
}

/// No partial import of a >50-file drag. The 100MB per-book maximum and
/// content signature checks are enforced later by importPickedBook/Store.
/// Passing streams does not read or keep any dropped content.
DesktopBookDropSelection classifyDesktopBookDrop(
  List<BatchPickedBook> selections, {
  int maxFiles = 50,
}) {
  if (maxFiles < 1 || maxFiles > 50) {
    throw ArgumentError.value(maxFiles, 'maxFiles');
  }
  if (selections.length > maxFiles) {
    throw const FormatException('At most 50 dropped files are supported');
  }

  final accepted = <BatchPickedBook>[];
  final rejected = <String>[];
  for (final item in selections) {
    final name = safeDroppedBookName(item.name);
    if (name.isEmpty || BookFormatPath.parse(name) == null) {
      rejected.add(name.isEmpty ? '(unnamed item)' : name);
      continue;
    }
    accepted.add(BatchPickedBook(
      name: name,
      // Never trust a drag item's provided OS path (or URI). A drop may
      // originate from a virtual/cloud provider. Read its stream while
      // the native onDrop callback is active instead.
      pickedPath: null,
      readAsByteStream: item.readAsByteStream,
    ));
  }
  return DesktopBookDropSelection(
    accepted: List<BatchPickedBook>.unmodifiable(accepted),
    unsupportedNames: List<String>.unmodifiable(rejected),
  );
}
