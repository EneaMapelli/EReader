import 'package:flutter/material.dart';

/// Explicit physical PDF page controls. Does not touch text anchors or TTS.
class PdfPageNavigation extends StatelessWidget {
  const PdfPageNavigation({
    super.key,
    required this.pageNumber,
    required this.pageCount,
    required this.onPageRequested,
    this.onZoomOut,
    this.onZoomIn,
  });

  final int pageNumber;
  final int? pageCount;
  final ValueChanged<int> onPageRequested;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;

  Future<void> _showPageJump(BuildContext context) async {
    final count = pageCount;
    if (count == null || count < 1) return;
    final formKey = GlobalKey<FormState>();
    var entered = '$pageNumber';
    int? chosen;
    chosen = await showDialog<int>(
      context: context,
      builder: (dialog) {
        void submit() {
          if (formKey.currentState?.validate() == true) {
            Navigator.pop(dialog, int.parse(entered.trim()));
          }
        }

        return AlertDialog(
          title: const Text('Go to PDF page'),
          content: Form(
            key: formKey,
            child: TextFormField(
              key: const ValueKey('pdf-page-input'),
              initialValue: entered,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Page number',
                helperText: 'Between 1 and $count',
              ),
              onChanged: (value) => entered = value,
              validator: (raw) {
                final page = int.tryParse((raw ?? '').trim());
                if (page == null || page < 1 || page > count) {
                  return 'Choose a page from 1 to $count';
                }
                return null;
              },
              onFieldSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submit,
              child: const Text('Go'),
            ),
          ],
        );
      },
    );
    if (chosen != null && context.mounted) onPageRequested(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final count = pageCount ?? 0;
    final ready = count > 0;
    final current = ready ? pageNumber.clamp(1, count).toInt() : pageNumber;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
        IconButton(
          tooltip: 'Previous PDF page',
          onPressed: ready && current > 1
              ? () => onPageRequested(current - 1)
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        TextButton(
          key: const ValueKey('pdf-current-page'),
          onPressed: ready ? () => _showPageJump(context) : null,
          child: Text(ready ? '$current / $count' : '$pageNumber / …'),
        ),
        IconButton(
          tooltip: 'Next PDF page',
          onPressed: ready && current < count
              ? () => onPageRequested(current + 1)
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
        if (onZoomOut != null)
          IconButton(
            tooltip: 'Zoom out PDF',
            onPressed: ready ? onZoomOut : null,
            icon: const Icon(Icons.zoom_out),
          ),
        if (onZoomIn != null)
          IconButton(
            tooltip: 'Zoom in PDF',
            onPressed: ready ? onZoomIn : null,
            icon: const Icon(Icons.zoom_in),
          ),
          ],
        ),
        // This uses PHYSICAL pages, not extracted text offsets. A scanned
        // PDF can use it without OCR or a synthesized speech checkpoint.
        if (count > 1)
          _PdfPageScrubber(
            pageNumber: current,
            pageCount: count,
            onPageRequested: onPageRequested,
          ),
      ],
    );
  }
}

/// Fast physical-page navigation for long or scanned PDFs.
///
/// A drag is a local preview only. It never calls onPageRequested until
/// release, avoiding hundreds of native PDF decoder page loads while the
/// user scrubs or any mutation of a separate TTS source checkpoint.
/// The existing page number dialog remains the exact jump mechanism.
class _PdfPageScrubber extends StatefulWidget {
  const _PdfPageScrubber({
    required this.pageNumber,
    required this.pageCount,
    required this.onPageRequested,
  });

  final int pageNumber;
  final int pageCount;
  final ValueChanged<int> onPageRequested;

  @override
  State<_PdfPageScrubber> createState() => _PdfPageScrubberState();
}

class _PdfPageScrubberState extends State<_PdfPageScrubber> {
  int? _previewPage;

  @override
  void didUpdateWidget(covariant _PdfPageScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pageCount != oldWidget.pageCount) {
      // Never keep a stale drag coordinate after document replacement.
      _previewPage = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.pageCount;
    final shown = (_previewPage ?? widget.pageNumber)
        .clamp(1, count).toInt();
    final percent = ((shown - 1) * 100 / (count - 1)).round();
    return Row(
      children: [
        const SizedBox(width: 8),
        SizedBox(
          width: 58,
          child: Text(
            '$percent%',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        Expanded(
          child: Slider(
            key: const ValueKey('pdf-page-scrubber'),
            value: shown.toDouble(),
            min: 1,
            max: count.toDouble(),
            // Avoid huge semantics/slider ticks for multi-thousand-page
            // technical manuals. The existing Go-to-page dialog is exact.
            divisions: count <= 201 ? count - 1 : 200,
            label: 'PDF page $shown of $count',
            semanticFormatterCallback: (value) =>
                'PDF page ${value.round()} of $count',
            onChanged: (value) => setState(() {
              _previewPage = value.round().clamp(1, count).toInt();
            }),
            onChangeEnd: (value) {
              final destination = value.round().clamp(1, count).toInt();
              setState(() => _previewPage = null);
              if (destination != widget.pageNumber) {
                widget.onPageRequested(destination);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

