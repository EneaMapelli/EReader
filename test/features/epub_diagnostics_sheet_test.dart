import 'package:ereader/data/epub_import_diagnostics.dart';
import 'package:ereader/features/reader/epub_diagnostics_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EPUB compatibility report explains skipped optional resources',
      (tester) async {
    const report = [
      EpubImportDiagnostic(EpubDiagnosticCode.rejectedImage, 3),
      EpubImportDiagnostic(EpubDiagnosticCode.unresolvedInternalLink, 2),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => FilledButton(
        onPressed: () => showEpubImportDiagnostics(context, report),
        child: const Text('Diagnostics'),
      ))),
    ));
    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('EPUB compatibility report'), findsOneWidget);
    expect(find.text('3×'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.textContaining('Embedded image'), findsOneWidget);
    expect(find.textContaining('Internal link'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('EPUB compatibility report'), findsNothing);
  });

  testWidgets('empty diagnostics give a neutral message, not an error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showEpubImportDiagnostics(context, const []),
        child: const Text('Report'),
      ))),
    ));
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('No compatibility warnings found'), findsOneWidget);
  });
}
