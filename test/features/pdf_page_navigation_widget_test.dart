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

  testWidgets('PDF physical page slider previews without navigating until release',
      (tester) async {
    final requests = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PdfPageNavigation(
        pageNumber: 4,
        pageCount: 30,
        onPageRequested: requests.add,
      )),
    ));
    const key = ValueKey('pdf-page-scrubber');
    final finder = find.byKey(key);
    expect(finder, findsOneWidget);
    expect(tester.widget<Slider>(finder).value, 4.0);

    final drag = await tester.startGesture(tester.getCenter(finder));
    await drag.moveBy(const Offset(70, 0));
    await tester.pump();
    expect(requests, isEmpty,
        reason: 'Moving a slider may not load a native PDF page');
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(requests, isEmpty);
    await drag.up();
    await tester.pump();
    expect(requests, hasLength(1),
        reason: 'Only the final committed page should load');
    expect(requests.single, inInclusiveRange(1, 30));
    expect(requests.single, isNot(4));
  });

  testWidgets('PDF page percentage and accessible label use physical pages',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PdfPageNavigation(
        pageNumber: 1,
        pageCount: 101,
        onPageRequested: (_) {},
      )),
    ));
    expect(find.text('0%'), findsOneWidget);
    var slider = tester.widget<Slider>(
        find.byKey(const ValueKey('pdf-page-scrubber')));
    expect(slider.value, 1.0);
    expect(slider.semanticFormatterCallback!(51), 'PDF page 51 of 101');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PdfPageNavigation(
        pageNumber: 101,
        pageCount: 101,
        onPageRequested: (_) {},
      )),
    ));
    expect(find.text('100%'), findsOneWidget);
    slider = tester.widget<Slider>(
        find.byKey(const ValueKey('pdf-page-scrubber')));
    expect(slider.value, 101.0);
    expect(slider.divisions, 100);
  });

  testWidgets('long PDF clamps preview density and retains exact page input',
      (tester) async {
    int? chosen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PdfPageNavigation(
        pageNumber: 1500,
        pageCount: 3000,
        onPageRequested: (page) => chosen = page,
      )),
    ));
    expect(find.text('50%'), findsOneWidget);
    final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('pdf-page-scrubber')));
    expect(slider.divisions, 200);
    await tester.tap(find.byKey(const ValueKey('pdf-current-page')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('pdf-page-input')), '2537');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(chosen, 2537,
        reason: 'The exact dialog is unaffected by coarse slider ticks');
  });

  testWidgets('PDF page slider absent until multi-page document is loaded',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PdfPageNavigation(
        pageNumber: 1,
        pageCount: null,
        onPageRequested: (_) => fail('Uninitialized PDF'),
      )),
    ));
    expect(find.byKey(const ValueKey('pdf-page-scrubber')), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PdfPageNavigation(
        pageNumber: 1,
        pageCount: 1,
        onPageRequested: (_) => fail('Single-page PDF'),
      )),
    ));
    expect(find.byKey(const ValueKey('pdf-page-scrubber')), findsNothing);
    expect(find.text('1 / 1'), findsOneWidget);
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
