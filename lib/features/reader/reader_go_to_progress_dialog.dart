import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/reading_progress.dart';

/// Only whole percentages may become explicit book-location seeks.
int? parseReaderProgressPercent(String raw) {
  final trimmed = raw.trim();
  if (!RegExp(r'^[0-9]{1,3}$').hasMatch(trimmed)) return null;
  final percentage = int.tryParse(trimmed);
  if (percentage == null || percentage > 100) return null;
  return percentage;
}

/// Exact canonical-source coordinates, never audio-duration estimates.
int readerProgressOffsetForPercent(int percent, int sourceLength) {
  if (percent < 0 || percent > 100 || sourceLength <= 0) {
    throw ArgumentError('Expected percentage 0..100 and nonempty text');
  }
  return ReadingSourceProgress.offsetForFraction(
    fraction: percent / 100,
    length: sourceLength,
  );
}

/// Canceling or editing never alters the book; only Go returns a new offset.
Future<int?> showReaderGoToProgressDialog(
  BuildContext context, {
  required int currentSourceOffset,
  required int sourceLength,
  bool autofocus = false,
}) async {
  if (sourceLength <= 0) return null;
  final current = ReadingSourceProgress.percentage(
    offset: currentSourceOffset,
    length: sourceLength,
  );
  final percent = await showDialog<int>(
    context: context,
    builder: (_) => _ReaderProgressDialog(
      current: current,
      autofocus: autofocus,
    ),
  );
  if (percent == null) return null;
  return readerProgressOffsetForPercent(percent, sourceLength);
}

class _ReaderProgressDialog extends StatefulWidget {
  const _ReaderProgressDialog({
    required this.current,
    required this.autofocus,
  });
  final int current;
  final bool autofocus;

  @override
  State<_ReaderProgressDialog> createState() => _ReaderProgressDialogState();
}

class _ReaderProgressDialogState extends State<_ReaderProgressDialog> {
  late final TextEditingController _controller;
  late int? _target;

  @override
  void initState() {
    super.initState();
    _target = widget.current;
    _controller = TextEditingController(text: widget.current.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _choose(int percent) {
    _controller.text = percent.toString();
    setState(() => _target = percent);
  }

  void _confirm() {
    final target = _target;
    if (target == null) return;
    Navigator.of(context).pop(target);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Go to book position'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose a percentage of the original book text. '
                'This is not estimated audio time or a PDF page.',
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('reader-progress-percent'),
                controller: _controller,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: InputDecoration(
                  labelText: 'Book position',
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                  errorText: _target == null
                      ? 'Enter a whole number between 0 and 100'
                      : null,
                ),
                onChanged: (value) =>
                    setState(() => _target = parseReaderProgressPercent(value)),
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final percent in const [0, 25, 50, 75, 100])
                    ChoiceChip(
                      key: ValueKey('reader-progress-preset-' +
                          percent.toString()),
                      label: Text(percent.toString() + '%'),
                      selected: _target == percent,
                      onSelected: (_) => _choose(percent),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('reader-progress-confirm'),
            onPressed: _target == null ? null : _confirm,
            child: const Text('Go'),
          ),
        ],
      );
}
