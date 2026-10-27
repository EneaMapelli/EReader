import 'dart:io';

import '../domain/book.dart';
import 'picked_book_import.dart';

/// A single native-picker selection. Never retain provider/cloud URIs:
/// importing copies the validated book into EReader's private library.
class BatchPickedBook {
  const BatchPickedBook({
    required this.name,
    required this.pickedPath,
    required this.readAsByteStream,
  });

  final String name;
  final String? pickedPath;
  final Stream<List<int>> Function() readAsByteStream;
}

enum BookImportOutcome { added, alreadyPresent, invalid, unavailable, failed }

class BatchBookImportEntry {
  const BatchBookImportEntry({
    required this.name,
    required this.outcome,
    this.book,
  });

  final String name;
  final BookImportOutcome outcome;
  final BookRecord? book;
}

/// Processing is serial by design: a batch of big PDFs/EPUBs must not load
/// all selected files into memory. Each import owns its own stream staging,
/// dedup, metadata and SQLite transaction. A failed item never prevents
/// importing later items.
class BatchBookImportResult {
  const BatchBookImportResult({
    required this.selectedCount,
    required this.entries,
  });

  final int selectedCount;
  final List<BatchBookImportEntry> entries;

  int get completedCount => entries.length;
  int get notProcessedCount => selectedCount - entries.length;
  int get addedCount =>
      entries.where((item) => item.outcome == BookImportOutcome.added).length;
  int get existingCount => entries
      .where((item) => item.outcome == BookImportOutcome.alreadyPresent)
      .length;
  int get failedCount => entries.where((item) =>
      item.outcome != BookImportOutcome.added &&
      item.outcome != BookImportOutcome.alreadyPresent).length;

  BookRecord? get onlySuccessfulBook =>
      selectedCount == 1 && entries.length == 1 &&
      entries.single.book != null ? entries.single.book : null;
}

/// Import a bounded batch and report each result, without leaking exception
/// messages, filesystem paths, private book content or Android SAF URIs.
/// Duplicate source hashes return their existing BookRecord unchanged.
Future<BatchBookImportResult> importPickedBooks({
  required List<BatchPickedBook> selections,
  required PickedBookImporter<BookRecord> importFile,
  required Iterable<String> knownBookIds,
  void Function(int completed, int total)? onProgress,
  bool Function()? cancelRemaining,
  Directory? stagingParent,
  int maxSelections = 50,
}) async {
  if (maxSelections < 1 || maxSelections > 50) {
    throw ArgumentError.value(maxSelections, 'maxSelections');
  }
  if (selections.length > maxSelections) {
    throw const FormatException('Too many files selected (maximum 50)');
  }
  final known = knownBookIds.toSet();
  final processed = <BatchBookImportEntry>[];
  for (final chosen in selections) {
    if (cancelRemaining?.call() ?? false) break;
    try {
      final imported = await importPickedBook<BookRecord>(
        originalName: chosen.name,
        pickedPath: chosen.pickedPath,
        readAsByteStream: chosen.readAsByteStream,
        importFile: importFile,
        stagingParent: stagingParent,
      );
      processed.add(BatchBookImportEntry(
        name: chosen.name,
        book: imported,
        outcome: known.add(imported.id)
            ? BookImportOutcome.added
            : BookImportOutcome.alreadyPresent,
      ));
    } on FormatException {
      processed.add(BatchBookImportEntry(
        name: chosen.name, outcome: BookImportOutcome.invalid,
      ));
    } on FileSystemException {
      processed.add(BatchBookImportEntry(
        name: chosen.name, outcome: BookImportOutcome.unavailable,
      ));
    } on PathNotFoundException {
      processed.add(BatchBookImportEntry(
        name: chosen.name, outcome: BookImportOutcome.unavailable,
      ));
    } catch (_) {
      processed.add(BatchBookImportEntry(
        name: chosen.name, outcome: BookImportOutcome.failed,
      ));
    }
    onProgress?.call(processed.length, selections.length);
  }
  return BatchBookImportResult(
      selectedCount: selections.length,
      entries: List<BatchBookImportEntry>.unmodifiable(processed));
}
