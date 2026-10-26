import 'package:flutter/material.dart';

/// Explicit physical PDF page controls. Does not touch text anchors or TTS.
class PdfPageNavigation extends StatelessWidget {
  const PdfPageNavigation({
    super.key,
    required this.pageNumber,
    required this.pageCount,
    required this.onPageRequested,
  });

  final int pageNumber;
  final int? pageCount;
  final ValueChanged<int> onPageRequested;

  Future<void> _showPageJump(BuildContext context) async {
    final count = pageCount;
    if (count == null || count < 1) return;
    final controller = TextEditingController(text: '$pageNumber');
    int? chosen;
    try {
      chosen = await showDialog<int>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Go to PDF page'),
          content: TextField(
            key: const ValueKey('pdf-page-input'),
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Page number',
              helperText: 'Between 1 and $count',
            ),
            onSubmitted: (text) {
              final requested = int.tryParse(text.trim());
              if (requested != null && requested >= 1 &&
                  requested <= count) {
                Navigator.pop(dialog, requested);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final requested = int.tryParse(controller.text.trim());
                if (requested != null && requested >= 1 &&
                    requested <= count) {
                  Navigator.pop(dialog, requested);
                }
              },
              child: const Text('Go'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (chosen != null && context.mounted) onPageRequested(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final count = pageCount;
    final ready = count != null && count > 0;
    final current = ready ? pageNumber.clamp(1, count) : pageNumber;
    return Row(
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
      ],
    );
  }
}
