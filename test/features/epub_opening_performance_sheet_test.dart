import 'package:ereader/data/epub_reader_preflight.dart';
import 'package:ereader/features/reader/epub_opening_performance_sheet.dart';
import 'package:ereader/features/reader/epub_frame_sampler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const worker = EpubPreflightTimings(
    archiveReadUs: 2500,
    xhtmlExtractionUs: 12300,
    speechSegmentationUs: 3100,
    quoteGroupingUs: 1400,
    paragraphBoundariesUs: 800,
    workerTotalUs: 23000,
    compressedBytes: 4096,
    sourceCodeUnits: 14000,
    spineItems: 7,
    speechSegments: 102,
    resumeRecoveryUs: 1800,
  );

  testWidgets('local opening metrics show only stage numbers, not book text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showEpubOpeningPerformance(
          context,
          worker: worker,
          castLayoutUs: 24000,
          voiceSetupUs: 5400,
          totalOpenUs: 70000,
          firstFrameUs: 85000,
        ),
        child: const Text('Inspect opening'),
      ))),
    ));
    await tester.tap(find.text('Inspect opening'));
    await tester.pumpAndSettle();
    expect(find.text('EPUB opening performance'), findsOneWidget);
    expect(find.text('Read ZIP bytes'), findsOneWidget);
    expect(find.text('2.5 ms'), findsOneWidget);
    expect(find.text('12.3 ms'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Verify saved reading position'), 120,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('1.8 ms'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('70.0 ms'), 120,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('70.0 ms'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('85.0 ms'), 120,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('85.0 ms'), findsOneWidget);
    expect(find.text('Local wall-clock measurements; no book text is '
        'recorded. Peak memory and frame-rate are not measured.'),
        findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('4096 bytes'), 120,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('4096 bytes'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('EPUB opening performance'), findsNothing);
  });

  testWidgets('empty/zero stage times are displayed without errors',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => FilledButton(
        onPressed: () => showEpubOpeningPerformance(
          context,
          worker: const EpubPreflightTimings(
            archiveReadUs: 0, xhtmlExtractionUs: 0,
            speechSegmentationUs: 0, quoteGroupingUs: 0,
            paragraphBoundariesUs: 0, workerTotalUs: 0,
            compressedBytes: 0, sourceCodeUnits: 0,
            spineItems: 0, speechSegments: 0,
          ),
          castLayoutUs: 0, voiceSetupUs: 0, totalOpenUs: 0,
        ),
        child: const Text('Inspect'),
      ))),
    ));
    await tester.tap(find.text('Inspect'));
    await tester.pumpAndSettle();
    expect(find.text('0.0 ms'), findsWidgets);
    await tester.scrollUntilVisible(
        find.text('0 bytes'), 120,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('0 bytes'), findsOneWidget);
  });
  testWidgets('frame capture starts only by explicit action, and report '
      'shows bounded numeric timings', (tester) async {
    var started = 0;
    final collector = EpubFrameSampler(maxFrames: 4)
      ..record(buildUs: 19000, rasterUs: 2000, totalUs: 24000)
      ..record(buildUs: 7000, rasterUs: 21000, totalUs: 30000);
    final report = collector.snapshot();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showEpubOpeningPerformance(
          context,
          worker: worker,
          castLayoutUs: 100,
          voiceSetupUs: 100,
          totalOpenUs: 300,
          frameProfile: report,
          onStartFrameCapture: () => started++,
        ),
        child: const Text('Inspect frames'),
      ))),
    ));
    await tester.tap(find.text('Inspect frames'));
    await tester.pumpAndSettle();
    expect(started, 0);
    await tester.scrollUntilVisible(
      find.text('On-demand reader frame sample'), 140,
      scrollable: find.byType(Scrollable).last,
    );
    // The count is a lazy ListView child below the section header.
    // First scrolling to the header doesn't materialize its rows.
    await tester.scrollUntilVisible(
      find.text('2 / 2'), 140,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('P95 frame raster'), 140,
      scrollable: find.byType(Scrollable).last,
    );
    // Raster P95 and slowest raster can both be 21.0 ms. Assert the value
    // in the intended metric row instead of requiring global uniqueness.
    final rasterP95Tile = find.ancestor(
      of: find.text('P95 frame raster'),
      matching: find.byType(ListTile),
    );
    expect(find.descendant(
      of: rasterP95Tile,
      matching: find.text('21.0 ms'),
    ), findsOneWidget);
    await tester.tap(find.text('Sample frames for 12 seconds'));
    await tester.pumpAndSettle();
    expect(started, 1);
    expect(find.text('EPUB opening performance'), findsNothing);
  });

  testWidgets('active capture can be stopped from report', (tester) async {
    var stopped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showEpubOpeningPerformance(
          context, worker: worker,
          castLayoutUs: 0, voiceSetupUs: 0, totalOpenUs: 0,
          frameCaptureActive: true,
          onStopFrameCapture: () => stopped++,
        ),
        child: const Text('Inspect active'),
      ))),
    ));
    await tester.tap(find.text('Inspect active'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop frame sample'));
    await tester.pumpAndSettle();
    expect(stopped, 1);
  });
}
