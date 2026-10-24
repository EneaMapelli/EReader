import 'package:ereader/data/epub_import_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostics group repeated resource failures into fixed categories', () {
    final report = EpubImportDiagnostics();
    report.record(EpubDiagnosticCode.rejectedImage);
    report.record(EpubDiagnosticCode.rejectedImage);
    report.record(EpubDiagnosticCode.unresolvedInternalLink);
    expect(report.items.length, 2);
    expect(report.items.singleWhere((i) =>
        i.code == EpubDiagnosticCode.rejectedImage).occurrences, 2);
    expect(report.items.every((entry) => entry.description.isNotEmpty),
        isTrue);
  });

  test('huge EPUB cannot grow unbounded diagnostics or warning text', () {
    final report = EpubImportDiagnostics();
    for (var i = 0; i < 11000; i++) {
      report.record(EpubDiagnosticCode.unresolvedInternalLink);
    }
    final items = report.items;
    expect(items.length, 1);
    expect(items.single.occurrences, 9999);
    expect(items.single.description, isNot(contains('http:')));
  });

  test('report snapshots are immutable and do not expose input URLs', () {
    final report = EpubImportDiagnostics();
    final snapshot = report.items;
    report.record(EpubDiagnosticCode.unavailableFootnote);
    expect(snapshot, isEmpty);
    expect(report.items.length, 1);
    expect(() => report.items.clear(), throwsUnsupportedError);
  });
}
