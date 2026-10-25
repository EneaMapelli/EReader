import 'package:flutter/material.dart';

import '../../data/epub_reader_preflight.dart';
import 'epub_frame_sampler.dart';

/// Read-only in-app instrumentation: numbers only; never sends a book title,
/// path, excerpt, voice, provider identity or credential to a log/service.
Future<void> showEpubOpeningPerformance(
  BuildContext context, {
  required EpubPreflightTimings worker,
  required int castLayoutUs,
  required int voiceSetupUs,
  required int totalOpenUs,
  int? firstFrameUs,
  EpubFrameProfile? frameProfile,
  bool frameCaptureActive = false,
  VoidCallback? onStartFrameCapture,
  VoidCallback? onStopFrameCapture,
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
                if (frameCaptureActive)
                  const ListTile(
                    title: Text('Frame sampling active'),
                    subtitle: Text('Scroll in the reader; the sample is '
                        'bounded to 12 seconds.'),
                  ),
                if (frameProfile != null) ...[
                  const ListTile(
                    title: Text('On-demand reader frame sample'),
                    subtitle: Text('Engine-reported, batched timings. '
                        'Not FPS, device-specific missed frames, or RAM. '
                        'A 16.7 ms threshold is only a 60 Hz reference.'),
                  ),
                  ListTile(
                    title: const Text('Completed frame samples'),
                    trailing: Text('${frameProfile.sampledFrames} / '
                        '${frameProfile.reportedFrames}'),
                  ),
                  if (frameProfile.sampledFrames > 0) ...[
                    timingRow('P95 frame build', frameProfile.p95BuildUs),
                    timingRow('P95 frame raster', frameProfile.p95RasterUs),
                    timingRow('P95 frame total latency',
                        frameProfile.p95TotalUs),
                    timingRow('Slowest sampled build',
                        frameProfile.maxBuildUs),
                    timingRow('Slowest sampled raster',
                        frameProfile.maxRasterUs),
                    ListTile(
                      title: const Text('Build over 16.7 ms (60 Hz reference)'),
                      trailing: Text('${frameProfile.overBudgetBuildFrames}'),
                    ),
                    ListTile(
                      title: const Text('Raster over 16.7 ms (60 Hz reference)'),
                      trailing: Text('${frameProfile.overBudgetRasterFrames}'),
                    ),
                  ] else
                    const ListTile(
                      title: Text('No completed frames were reported'),
                    ),
                ],
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
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  if (!frameCaptureActive && onStartFrameCapture != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onStartFrameCapture();
                      },
                      icon: const Icon(Icons.speed),
                      label: const Text('Sample frames for 12 seconds'),
                    ),
                  if (frameCaptureActive && onStopFrameCapture != null)
                    TextButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onStopFrameCapture();
                      },
                      child: const Text('Stop frame sample'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  },
);
