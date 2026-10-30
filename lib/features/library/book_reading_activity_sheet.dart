import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../domain/reading_activity.dart';

/// Detail of one book's measured local reading and listening totals.
/// The global daily goal is deliberately not attributed to individual books.
class BookReadingActivitySheet extends StatelessWidget {
  const BookReadingActivitySheet({
    super.key,
    required this.store,
    required this.bookId,
  });

  final LibraryStore store;
  final String bookId;

  Future<void> _confirmClearBook(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this book\'s activity?'),
        content: const Text(
          'Remove all recorded reading and TTS time for this book, '
          'including its historical days. This cannot be undone. '
          'The book, reading position and bookmarks remain unchanged. '
          'Previously exported backups are unaffected, and future activity '
          'for this book will continue to be recorded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete activity'),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
    store.clearReadingActivity(bookId: bookId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lifetime = store.bookReadingLifetimeTotals(bookId);
    final week = store.weeklyReadingActivity(bookId: bookId);
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('stats-book-detail'),
        height: MediaQuery.sizeOf(context).height * 0.70,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(lifetime.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'Close book reading details',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('All recorded activity',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Reading: ${formatReadingActivityDuration(lifetime.visualSeconds)}  '
              '· TTS: ${formatReadingActivityDuration(lifetime.ttsSeconds)}',
              key: const ValueKey('stats-book-lifetime'),
            ),
            const SizedBox(height: 22),
            Text('Last seven calendar days',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Reading: ${formatReadingActivityDuration(week.visualSeconds)}  '
              '· TTS: ${formatReadingActivityDuration(week.ttsSeconds)}',
              key: const ValueKey('stats-book-week'),
            ),
            const SizedBox(height: 12),
            for (final day in week.days)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(day.date),
                subtitle: Text(
                  'Reading ${formatReadingActivityDuration(day.visualSeconds)}'
                  ' · TTS ${formatReadingActivityDuration(day.ttsSeconds)}',
                  key: ValueKey('stats-book-day-${day.date}'),
                ),
              ),
            const SizedBox(height: 16),
            const Divider(),
            TextButton.icon(
              key: const ValueKey('stats-clear-book'),
              onPressed: () => _confirmClearBook(context),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Clear timed activity for this book'),
            ),
            const SizedBox(height: 16),
            Text(
              'These totals start when activity tracking was introduced. '
              'Visual time is a conservative interaction-based estimate; '
              'TTS time is based on playback state, not confirmed sound '
              'output. This view is read-only and all data stays on-device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
