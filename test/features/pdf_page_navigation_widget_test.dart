import 'package:ereader/features/reader/pdf_page_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PDF navigation shows page count and obeys both boundaries',
      (tester) async {
    final requested = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfPageNavigation(
          pageNumber: 1,
          pageCount: 14,
          onPageRequested: requested.add,
        ),
      ),
    ));
    expect(find.text('1 / 14'), findsOneWidget);
    expect(
      tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_left)).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Next PDF page'));
    expect(requested, [2]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfPageNavigation(
          pageNumber: 14,
          pageCount: 14,
          onPageRequested: requested.add,
        ),
      ),
    ));
    expect(
      tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Previous PDF page'));
    expect(requested.last, 13);
  });

  testWidgets('page jump rejects invalid page and accepts valid page',
      (tester) async {
    int? chosen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfPageNavigation(
          pageNumber: 2,
          pageCount: 7,
          onPageRequested: (page) => chosen = page,
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('pdf-current-page')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('pdf-page-input')), '99');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a page from 1 to 7'), findsOneWidget);
    expect(chosen, isNull);
    expect(find.text('Go to PDF page'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('pdf-page-input')), '5');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(chosen, 5);
    expect(find.text('Go to PDF page'), findsNothing);
  });

  testWidgets('PDF zoom buttons remain independent of page jumps',
      (tester) async {
    var zoomIn = 0;
    var zoomOut = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PdfPageNavigation(
        pageNumber: 3,
        pageCount: 7,
        onPageRequested: (_) => fail('Zoom must not change PDF page'),
        onZoomIn: () => zoomIn++,
        onZoomOut: () => zoomOut++,
      )),
    ));
    await tester.tap(find.byTooltip('Zoom in PDF'));
    await tester.tap(find.byTooltip('Zoom out PDF'));
    expect(zoomIn, 1);
    expect(zoomOut, 1);
    expect(find.text('3 / 7'), findsOneWidget);
  });

  testWidgets('uninitialized PDF viewer disables all page controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfPageNavigation(
          pageNumber: 1,
          pageCount: null,
          onPageRequested: (_) => fail('No navigation without loaded PDF'),
        ),
      ),
    ));
    expect(find.text('1 / …'), findsOneWidget);
    expect(tester.widget<TextButton>(
      find.byKey(const ValueKey('pdf-current-page'))).onPressed, isNull);
    expect(tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull);
  });
}
