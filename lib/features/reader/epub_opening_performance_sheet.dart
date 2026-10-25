import 'package:flutter/material.dart';

import '../../data/epub_reader_preflight.dart';

/// Read-only in-app instrumentation: numbers only; never sends a book title,
/// path, excerpt, voice, provider identity or credential to a log/service.
Future<void> showEpubOpeningPerformance(
  BuildContext context, {
  required EpubPreflightTimings worker,
  required int castLayoutUs,
  required int voiceSetupUs,
  required int totalOpenUs,
  int? firstFrameUs,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheetContext) {
    Widget timingRow(String name, int microseconds) => ListTile(
      dense: true,
      title: Text(name),
      trailing: Text('${(microseconds / 1000).toStringAsFixed(1)} ms'),
    );
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.75,
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.speed_outlined),
              title: Text('EPUB opening performance'),
              subtitle: Text(
                'Local wall-clock measurements; no book text is recorded. '
                'Peak memory and frame-rate are not measured.',
              ),
            ),
            Expanded(
              child: ListView(children: [
                timingRow('Read ZIP bytes', worker.archiveReadUs),
                timingRow('Extract XHTML source', worker.xhtmlExtractionUs),
                timingRow('Initial speech segments',
                    worker.speechSegmentationUs),
                timingRow('Identify dialogue regions', worker.quoteGroupingUs),
                timingRow('Paragraph boundaries',
                    worker.paragraphBoundariesUs),
                if (worker.resumeRecoveryUs != null)
                  timingRow('Verify saved reading position',
                      worker.resumeRecoveryUs!),
                timingRow('Worker preparation total', worker.workerTotalUs),
                timingRow('Cast and progressive layout', castLayoutUs),
                timingRow('Voice and reader setup', voiceSetupUs),
                timingRow('Total opening until reader state ready', totalOpenUs),
                if (firstFrameUs != null)
                  timingRow('First completed reader frame', firstFrameUs),
                ListTile(
                  title: const Text('EPUB archive size'),
                  trailing: Text('${worker.compressedBytes} bytes'),
                ),
                ListTile(
                  title: const Text('Readable UTF-16 code units'),
                  trailing: Text('${worker.sourceCodeUnits}'),
                ),
                ListTile(
                  title: const Text('Spine items'),
                  trailing: Text('${worker.spineItems}'),
                ),
                ListTile(
                  title: const Text('Initial speech segments'),
                  trailing: Text('${worker.speechSegments}'),
                ),
              ]),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  },
);
