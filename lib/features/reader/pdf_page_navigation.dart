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
    final count = pageCount;
    final ready = count != null && count > 0;
    final current = ready ? pageNumber.clamp(1, count).toInt() : pageNumber;
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
