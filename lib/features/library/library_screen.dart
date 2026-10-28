import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../data/batch_book_import.dart';
import '../../data/desktop_book_drop.dart';
import '../../data/picked_book_import.dart';
import '../../data/android_picker_recovery.dart';
import '../../audio/reader_media_handler.dart';
import '../../domain/book.dart';
import '../../domain/library_catalog.dart';
import '../reader/reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.store,
    this.mediaHandler,
    this.retrieveInterruptedPick,
  });
  final LibraryStore store;
  final ReaderMediaHandler? mediaHandler;

  /// Injectable for widget tests. Android uses native one-time lost-data
  /// recovery after the Activity is killed while the picker is in front.
  final Future<InterruptedBookSelection?> Function()? retrieveInterruptedPick;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _busy = false;
  bool _recoveringInterruptedPick = false;
  bool _dragHover = false;
  int _importCompleted = 0;
  int _importTotal = 0;
  int _backupTotal = 0;
  int _backupCompleted = 0;
  bool _exportingBackup = false;
  bool _restoringBackup = false;
  int _restoreTotal = 0;
  int _restoreDone = 0;
  bool _cancelRemainingImports = false;
  final _searchController = TextEditingController();
  String _query = '';
  BookFormat? _formatFilter;
  LibrarySortOrder _sortOrder = LibrarySortOrder.recentlyImported;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _formatFilter = null;
      _sortOrder = LibrarySortOrder.recentlyImported;
    });
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || widget.retrieveInterruptedPick != null) {
      // The plugin must be registered and the LibraryScreen mounted; use
      // the first frame instead of blocking app startup or widget build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_recoverInterruptedPick());
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _recoverInterruptedPick() async {
    if (!mounted || _busy || _recoveringInterruptedPick) return;
    _recoveringInterruptedPick = true;
    try {
      final selection = await
          (widget.retrieveInterruptedPick ?? recoverInterruptedAndroidBookPick)();
      if (!mounted || selection == null) return;
      if (selection.failed) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The previous Android book selection could not '
              'be recovered. You can choose the books again.'),
        ));
        return;
      }
      if (selection.selections.isNotEmpty) {
        await _import(recoveredBooks: selection.selections);
      }
    } catch (_) {
      // Never log exception text: OS providers can reveal full private URIs.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not recover the interrupted book selection. '
              'Please choose your books again.'),
        ));
      }
    } finally {
      _recoveringInterruptedPick = false;
    }
  }

  /// The picker supports single and multi-file selection on Windows and
  /// Android SAF. Files are imported sequentially, with isolated per-file
  /// errors and no automatic audio or cloud requests.
  Future<void> _import({List<BatchPickedBook>? recoveredBooks}) async {
    if (_busy || (_recoveringInterruptedPick && recoveredBooks == null)) {
      return;
    }
    setState(() => _busy = true);
    try {
      // Android's one-time lost-data pick uses exactly the same bounded
      // import path as an ordinary selection. Neither case uploads books.
      final List<BatchPickedBook> selected;
      if (recoveredBooks != null) {
        selected = recoveredBooks;
      } else {
        // v13 exposes streams even if Android SAF has no OS file path.
        final picked = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['epub', 'pdf', 'txt'],
        );
        selected = [
          for (final item in picked)
            BatchPickedBook(
              name: item.name,
              pickedPath: item.path,
              readAsByteStream: item.readAsByteStream,
            ),
        ];
      }
      if (!mounted || selected.isEmpty) return;
      if (selected.length > 50) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select at most 50 books per import.'),
        ));
        return;
      }
      setState(() {
        _importCompleted = 0;
        _importTotal = selected.length;
        _cancelRemainingImports = false;
      });
      final result = await importPickedBooks(
        selections: selected,
        importFile: widget.store.importFile,
        knownBookIds: widget.store.books.map((book) => book.id),
        cancelRemaining: () => _cancelRemainingImports || !mounted,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() {
              _importCompleted = completed;
              _importTotal = total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _importTotal = 0;
        _importCompleted = 0;
      });
      final onlyBook = result.onlySuccessfulBook;
      if (onlyBook != null && recoveredBooks == null) {
        await _open(onlyBook);
      } else if (onlyBook != null && recoveredBooks != null) {
        // On cold app restart, leave the user in their library rather
        // than unexpectedly opening a book or starting narration.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Recovered your interrupted book selection. '
              'The book is now in your library.'),
        ));
      } else if (result.selectedCount == 1 && result.failedCount == 1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The selected book could not be imported. '
              'Check the file format and read permissions.'),
        ));
      } else {
        await _showBatchImportReport(result);
      }
    } catch (_) {
      // File-system/SAF errors may contain private absolute filenames,
      // so never display or log the raw exception.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cannot import books. Check file picker access '
              'and available storage.'),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _importTotal = 0;
          _importCompleted = 0;
          _cancelRemainingImports = false;
        });
      }
    }
  }

  Future<void> _showBatchImportReport(
    BatchBookImportResult report, {
    List<String> unsupportedNames = const [],
  }) async {
    if (!mounted) return;
    // Only show sanitized display basenames from the native picker, never
    // private absolute paths or exception strings from failed decoders.
    String displayName(String text) {
      final name = text.replaceAll('\\', '/').split('/').last
          .replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();
      return name.length <= 70 ? name : '${name.substring(0, 67)}...';
    }
    final failures = report.entries.where((item) =>
        item.outcome != BookImportOutcome.added &&
        item.outcome != BookImportOutcome.alreadyPresent).toList();
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Book import summary'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Added: ${report.addedCount}'),
                Text('Already in library: ${report.existingCount}'),
                Text('Could not import: ${report.failedCount}'),
                if (unsupportedNames.isNotEmpty)
                  Text('Unsupported dropped files: ${unsupportedNames.length}'),
                if (report.notProcessedCount > 0)
                  Text('Cancelled / not processed: '
                      '${report.notProcessedCount}'),
                if (unsupportedNames.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Skipped (not EPUB, PDF or TXT):'),
                  for (final name in unsupportedNames.take(5))
                    Text('• ${displayName(name)}'),
                  if (unsupportedNames.length > 5)
                    Text('...and ${unsupportedNames.length - 5} more.'),
                ],
                if (failures.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Files to review:'),
                  for (final item in failures.take(10))
                    Text('• ${displayName(item.name)} — '
                        '${switch (item.outcome) {
                          BookImportOutcome.invalid => 'invalid or unsupported',
                          BookImportOutcome.unavailable => 'unavailable file',
                          _ => 'import failed',
                        }}'),
                  if (failures.length > 10)
                    Text('...and ${failures.length - 10} more.'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// Explorer may provide real or virtual/cloud-backed files. Consume
  /// every file stream inside onDrop before native provider access expires.
  /// No arbitrary URL/text/directory is downloaded or recursively traversed.
  Future<void> _receiveDroppedBooks(DropDetails details) async {
    if (_busy || !mounted) return;
    setState(() => _dragHover = false);
    final files = details.items.whereType<DropFileItem>().toList();
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Drop EPUB, PDF or TXT files (not folders or URLs).'),
      ));
      return;
    }

    late DesktopBookDropSelection dropped;
    try {
      dropped = classifyDesktopBookDrop([
        for (final item in files)
          BatchPickedBook(
            name: item.name,
            pickedPath: null,
            readAsByteStream: item.file.openRead,
          ),
      ]);
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Drag at most 50 files at a time.'),
      ));
      return;
    }
    if (dropped.accepted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No supported books found. '
            'Drop EPUB, PDF or TXT files, not folders.'),
      ));
      return;
    }

    setState(() {
      _busy = true;
      _importCompleted = 0;
      _importTotal = dropped.accepted.length;
      _cancelRemainingImports = false;
    });
    BatchBookImportResult? result;
    try {
      // Await all provider reads *before* returning from onDrop.
      result = await importPickedBooks(
        selections: dropped.accepted,
        importFile: widget.store.importFile,
        knownBookIds: widget.store.books.map((book) => book.id),
        cancelRemaining: () => _cancelRemainingImports || !mounted,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() {
              _importCompleted = completed;
              _importTotal = total;
            });
          }
        },
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cannot import dropped books. Check file '
              'permissions and available storage.'),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _importCompleted = 0;
          _importTotal = 0;
          _cancelRemainingImports = false;
        });
      }
    }

    if (result != null && mounted) {
      final completed = result;
      final unsupported = dropped.unsupportedNames;
      // The plugin releases provider resources only when this async
      // onDrop completes. The report dialog must not keep them alive.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_showBatchImportReport(
            completed, unsupportedNames: unsupported,
          ));
        }
      });
    }
  }

  Widget _batchImportProgress() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: _importTotal == 0
              ? null : _importCompleted / _importTotal,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: Text(
              'Importing books: $_importCompleted / $_importTotal',
              semanticsLabel: 'Book import progress',
            )),
            TextButton(
              onPressed: _cancelRemainingImports
                  ? null
                  : () => setState(() => _cancelRemainingImports = true),
              child: Text(_cancelRemainingImports
                  ? 'Stopping after this file' : 'Cancel remaining'),
            ),
          ],
        ),
      ],
    ),
  );

  /// A full SQLite/EPUB/PDF/TXT library snapshot is deliberately private,
  /// local and opt-in. Never persist destination paths or move native
  /// credential-vault secrets. No overwrite of existing backup folders.
  Future<void> _exportBackup() async {
    if (_busy || !mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Export private library backup?'),
        content: const Text(
          'EReader will copy your books, bookmarks, reading positions '
          'and library annotations to a folder you choose. '
          'The backup is NOT encrypted and may contain private reading '
          'history, character annotations and cloud-consent settings. '
          'Store it securely. Cloud API keys and OS secrets are NOT copied. '
          'Restore on another device is not available yet; never replace '
          'your live EReader database with these files manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Choose destination'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final destination = await FilePicker.getDirectoryPath();
    if (destination == null || !mounted) return;
    setState(() {
      _busy = true;
      _exportingBackup = true;
      _backupTotal = widget.store.books.length;
      _backupCompleted = 0;
    });
    try {
      final result = await widget.store.exportLibraryBackup(
        Directory(destination),
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _backupCompleted = done;
              _backupTotal = total;
            });
          }
        },
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Library backup exported'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Verified books: ${result.bookCount}'),
                Text('Copied: ${(result.bookBytes / (1024 * 1024))
                    .toStringAsFixed(1)} MiB'),
                const SizedBox(height: 12),
                const Text('Keep this private folder safe:'),
                SelectableText(result.directory.path),
                const SizedBox(height: 12),
                const Text('No cloud upload was performed. '
                    'Automatic restore is not available yet.'),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        // Do not leak internal filesystem paths or private database data
        // from raw SQLite/IO exception messages into the UI.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Backup could not be completed. Verify that '
              'all books are present and the destination has free space. '
              'No completed backup folder was created.'),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _exportingBackup = false;
          _backupTotal = 0;
          _backupCompleted = 0;
        });
      }
    }
  }

  /// Preview validates the entire archive without touching local books.
  /// A second, explicit confirmation is needed before importing anything.
  Future<void> _restoreBackup() async {
    if (_busy || !mounted) return;
    final destination = await FilePicker.getDirectoryPath();
    if (destination == null || !mounted) return;
    final folder = Directory(destination);
    setState(() {
      _busy = true;
      _restoringBackup = true;
      _restoreDone = 0;
      _restoreTotal = 0;
    });
    try {
      final preview = await widget.store.previewLibraryRestore(folder);
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Restore books from backup?'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Backup verified: ${preview.total} books'),
                  Text('New books to import: ${preview.availableToImport}'),
                  Text('Already in your library: ${preview.alreadyPresent}'),
                  Text('New bookmarks: ${preview.bookmarksToImport}'),
                  Text('Verified source bytes: '
                      '${(preview.verifiedBytes / (1024 * 1024))
                          .toStringAsFixed(1)} MiB'),
                  const SizedBox(height: 12),
                  const Text(
                    'Existing books, their positions, bookmarks and '
                    'settings will NOT be changed. New books regain '
                    'saved positions, bookmarks and catalog details. '
                    'Cloud/LLM consent, API keys, cached audio, voice '
                    'choices and cast data are NOT imported. '
                    'The process is add-only; earlier successfully '
                    'restored books stay imported if a later book fails.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: preview.availableToImport == 0
                  ? null : () => Navigator.pop(dialog, true),
              child: const Text('Restore new books'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      setState(() {
        _restoreTotal = preview.total;
        _restoreDone = 0;
      });
      final result = await widget.store.restoreLibraryBackup(
        folder,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _restoreDone = done;
              _restoreTotal = total;
            });
          }
        },
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Library restore complete'),
          content: Text(
            'Imported: ${result.added} books\n'
            'Kept unchanged: ${result.skipped} books\n'
            'Bookmarks restored: ${result.bookmarksImported}\n\n'
            'No cloud permissions or API keys were imported.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'Cannot restore this backup. Check folder integrity and '
            'disk space. Existing books were not overwritten; if '
            'restoration stopped midway, some new books may already '
            'have been imported.',
          ),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _restoringBackup = false;
          _restoreDone = 0;
          _restoreTotal = 0;
        });
      }
    }
  }

  Future<void> _open(BookRecord book) async {
    try {
      await widget.store.markBookOpened(book.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: book, store: widget.store,
            mediaHandler: widget.mediaHandler,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot reopen book: $error')),
        );
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _editMetadata(BookRecord book) async {
    if (_busy || !mounted) return;
    var title = book.title;
    var author = book.author ?? '';
    var series = book.series ?? '';
    var language = book.language ?? '';
    final entered = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Edit book details'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('book-edit-title'),
                  initialValue: title,
                  onChanged: (value) => title = value,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextFormField(
                  key: const ValueKey('book-edit-author'),
                  initialValue: author,
                  onChanged: (value) => author = value,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Author'),
                ),
                TextFormField(
                  key: const ValueKey('book-edit-series'),
                  initialValue: series,
                  onChanged: (value) => series = value,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Series'),
                ),
                TextFormField(
                  key: const ValueKey('book-edit-language'),
                  initialValue: language,
                  onChanged: (value) => language = value,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: 'Language (e.g. it-IT)',
                    helperText: 'TTS voice is configured separately.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          if (book.format == BookFormat.epub)
            TextButton(
              onPressed: () => Navigator.pop(dialog, {
                'action': 'fill-missing',
              }),
              child: const Text('Fill from EPUB'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, {
              'title': title,
              'author': author,
              'series': series,
              'language': language,
            }),
            child: const Text('Save details'),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return;
    try {
      if (entered['action'] == 'fill-missing') {
        await widget.store.fillMissingEpubMetadata(book.id);
        if (mounted) setState(() {});
        return;
      }
      widget.store.updateBookMetadata(
        book.id,
        title: entered['title'] ?? '',
        author: entered['author'],
        series: entered['series'],
        language: entered['language'],
      );
      setState(() {});
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } on FileSystemException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
              'EPUB file is missing or cannot be read.')),
        );
      }
    } on StateError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book is no longer in the library.')),
        );
      }
    }
  }

  Future<void> _remove(BookRecord book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove book?'),
        content: Text('Remove "${book.title}" from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.removeBook(book.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final allBooks = widget.store.books;
    final books = filterAndSortLibraryBooks(
      allBooks, query: _query, format: _formatFilter, sort: _sortOrder,
    );
    final lastOpened = widget.store.lastOpenedBook;
    final interrupted = widget.store.interruptedNarrationBook;
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('EReader'),
        actions: [
          IconButton(
            tooltip: 'Restore books from library backup',
            onPressed: _busy ? null : _restoreBackup,
            icon: const Icon(Icons.restore),
          ),
          IconButton(
            tooltip: 'Export private library backup',
            onPressed: _busy ? null : _exportBackup,
            icon: const Icon(Icons.backup_outlined),
          ),
          IconButton(
            tooltip: 'Import book',
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      body: allBooks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_stories_outlined, size: 64),
                  const SizedBox(height: 12),
                  const Text('Your library is empty'),
                  const SizedBox(height: 8),
                  const Text('Import a TXT, EPUB, or PDF to begin'),
                  if (Platform.isWindows) ...[
                    const SizedBox(height: 8),
                    const Text('Or drag ebook files here from Windows Explorer'),
                  ],
                  if (_importTotal > 0) _batchImportProgress(),
                  if (_exportingBackup)
                    Text('Backing up books: $_backupCompleted / $_backupTotal'),
                  if (_restoringBackup && _restoreTotal == 0)
                    const Text('Checking library backup integrity...'),
                  if (_restoringBackup && _restoreTotal > 0)
                    Text('Restoring books: $_restoreDone / $_restoreTotal'),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.add),
                    label: const Text('Import book'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (Platform.isWindows && !_busy)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.file_upload_outlined, size: 16),
                        SizedBox(width: 6),
                        Flexible(child: Text(
                          'Drop EPUB, PDF or TXT here to import',
                          textAlign: TextAlign.center,
                        )),
                      ],
                    ),
                  ),
                if (_importTotal > 0) _batchImportProgress(),
                if (_restoringBackup && _restoreTotal == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        LinearProgressIndicator(),
                        Text('Checking backup integrity...'),
                      ],
                    ),
                  ),
                if (_restoringBackup && _restoreTotal > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: _restoreDone / _restoreTotal,
                        ),
                        Text('Restoring books: '
                            '$_restoreDone / $_restoreTotal'),
                      ],
                    ),
                  ),
                if (_exportingBackup)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: _backupTotal > 0
                              ? _backupCompleted / _backupTotal : null,
                        ),
                        Text('Backing up books: '
                            '$_backupCompleted / $_backupTotal'),
                      ],
                    ),
                  ),
                if (interrupted != null)
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: ListTile(
                      leading: const Icon(Icons.settings_backup_restore),
                      title: const Text('Narration interrupted'),
                      subtitle: Text(
                        '${interrupted.title} · Reopen at the saved position. '
                        'Audio will not start automatically.',
                      ),
                      isThreeLine: true,
                      onTap: _busy ? null : () => _open(interrupted),
                      trailing: IconButton(
                        tooltip: 'Dismiss interrupted narration notice',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          widget.store.dismissInterruptedNarration();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                if (lastOpened != null)
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('Continue reading'),
                      subtitle: Text(
                        '${lastOpened.title} · character ${lastOpened.progressOffset}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _busy ? null : () => _open(lastOpened),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: TextField(
                    key: const ValueKey('library-search'),
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      labelText: 'Search library',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _query.isEmpty ? null : IconButton(
                        tooltip: 'Clear library search',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Row(
                    children: [
                      const Text('Sort'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<LibrarySortOrder>(
                          key: const ValueKey('library-sort'),
                          value: _sortOrder,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: LibrarySortOrder.recentlyImported,
                              child: Text('Recently imported')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.titleAscending,
                              child: Text('Title A–Z')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.titleDescending,
                              child: Text('Title Z–A')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.authorAscending,
                              child: Text('Author A–Z')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.seriesAscending,
                              child: Text('Series A–Z')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.format,
                              child: Text('File format')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _sortOrder = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Row(
                    children: [
                      for (final format in <BookFormat?>[
                        null, BookFormat.epub, BookFormat.pdf, BookFormat.txt,
                      ]) ...[
                        ChoiceChip(
                          key: ValueKey('library-filter-${format?.name ?? 'all'}'),
                          label: Text(format?.name.toUpperCase() ?? 'All'),
                          selected: _formatFilter == format,
                          onSelected: (_) =>
                              setState(() => _formatFilter = format),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: books.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('No books match your filters.'),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _clearFilters,
                                child: const Text('Clear filters'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return ListTile(
                        leading: LibraryBookCover(
                          key: ValueKey('cover-tile-${book.id}'),
                          store: widget.store,
                          book: book,
                        ),
                        title: Text(book.title),
                        subtitle: Text(
                          [
                            if (book.author != null) book.author!,
                            if (book.series != null) book.series!,
                            if (book.language != null) book.language!,
                            book.format.name.toUpperCase(),
                            'saved at character ${book.progressOffset}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: _busy ? null : () => _open(book),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit book details',
                              onPressed: _busy ? null : () => _editMetadata(book),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove book',
                              onPressed: _busy ? null : () => _remove(book),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: allBooks.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.add),
              label: const Text('Import'),
            )
          : null,
    );
    // Keep Android entirely on the existing SAF picker path. The native
    // Windows receiver is active only while the library is idle.
    if (!Platform.isWindows) return scaffold;
    return DropTarget(
      key: const ValueKey('library-desktop-drop-target'),
      acceptedKinds: const {DropItemKind.file},
      enabled: !_busy,
      onEnter: (_) {
        if (!_dragHover && mounted) setState(() => _dragHover = true);
      },
      onLeave: () {
        if (_dragHover && mounted) setState(() => _dragHover = false);
      },
      onDrop: _receiveDroppedBooks,
      child: Stack(
        fit: StackFit.expand,
        children: [
          scaffold,
          if (_dragHover)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('library-drag-overlay'),
                  alignment: Alignment.center,
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.14),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_upload_outlined, size: 52),
                        SizedBox(height: 10),
                        Text(
                          'Drop EPUB, PDF or TXT books here',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text('Up to 50 files · Folders and URLs are ignored'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// EPUB covers are read from the existing cache synchronously. PDF previews
/// are generated lazily only for visible rows and never block importing,
/// searching or opening a book. A failed render keeps the format icon.
class LibraryBookCover extends StatefulWidget {
  const LibraryBookCover({
    super.key,
    required this.store,
    required this.book,
  });

  final LibraryStore store;
  final BookRecord book;

  @override
  State<LibraryBookCover> createState() => _LibraryBookCoverState();
}

class _LibraryBookCoverState extends State<LibraryBookCover> {
  Future<File?>? _pending;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant LibraryBookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id ||
        oldWidget.store != widget.store) {
      _loadIfNeeded();
    }
  }

  void _loadIfNeeded() {
    _pending = widget.book.format == BookFormat.pdf &&
            widget.store.coverFile(widget.book.id) == null
        ? widget.store.ensurePdfCover(widget.book.id)
        : null;
  }

  Widget _fallback() => Icon(
        widget.book.format == BookFormat.pdf
            ? Icons.picture_as_pdf_outlined
            : Icons.menu_book_outlined,
      );

  Widget _image(File file) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          key: ValueKey('library-cover-${widget.book.id}'),
          width: 40,
          height: 56,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: 120,
            errorBuilder: (_, __, ___) => Center(child: _fallback()),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final existing = widget.store.coverFile(widget.book.id);
    if (existing != null) return _image(existing);
    final pending = _pending;
    if (pending == null) return _fallback();
    return FutureBuilder<File?>(
      future: pending,
      builder: (context, result) =>
          result.data == null ? _fallback() : _image(result.data!),
    );
  }
}
