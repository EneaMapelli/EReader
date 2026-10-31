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
import '../../data/android_shared_book_inbox.dart';
import '../../audio/reader_media_handler.dart';
import '../../domain/book.dart';
import '../../domain/library_catalog.dart';
import '../../domain/library_search_query.dart';
import '../../domain/library_full_text.dart';
import '../../domain/library_reading_statistics.dart';
import 'library_reading_statistics_sheet.dart';
import '../reader/reader_screen.dart';
import 'library_collections_sheet.dart';
import 'library_full_text_search_sheet.dart';
import 'library_keyboard_shortcuts.dart';
import '../shared/organized_action_sheet.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.store,
    this.mediaHandler,
    this.retrieveInterruptedPick,
    this.sharedBookInbox,
  });
  final LibraryStore store;
  final ReaderMediaHandler? mediaHandler;

  /// Injectable for widget tests. Android uses native one-time lost-data
  /// recovery after the Activity is killed while the picker is in front.
  final Future<InterruptedBookSelection?> Function()? retrieveInterruptedPick;
  /// Injectable native receiver for Android share-sheet widget tests.
  final AndroidSharedBookInbox? sharedBookInbox;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _busy = false;
  bool _recoveringInterruptedPick = false;
  bool _processingSharedBooks = false;
  AndroidSharedBookInbox? _sharedInbox;
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
  final _librarySearchFocus = FocusNode(debugLabel: 'Library search');
  String _query = '';
  BookFormat? _formatFilter;
  bool _favoritesOnly = false;
  BookReadingStatus? _readingStatusFilter;
  String? _collectionFilterId;
  LibraryActivityFilter _activityFilter = LibraryActivityFilter.all;
  LibrarySortOrder _sortOrder = LibrarySortOrder.recentlyImported;
  bool _smallFiltersExpanded = false;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _formatFilter = null;
      _favoritesOnly = false;
      _readingStatusFilter = null;
      _collectionFilterId = null;
      _activityFilter = LibraryActivityFilter.all;
      _sortOrder = LibrarySortOrder.recentlyImported;
    });
  }

  @override
  void initState() {
    super.initState();
    _sharedInbox = widget.sharedBookInbox ??
        (Platform.isAndroid ? MethodChannelAndroidSharedBookInbox() : null);
    _sharedInbox?.listen(() => unawaited(_consumeSharedBooks()));
    if (_sharedInbox != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_consumeSharedBooks());
      });
    }
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
    _sharedInbox?.dispose();
    _searchController.dispose();
    _librarySearchFocus.dispose();
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
      if (mounted) unawaited(_consumeSharedBooks());
    }
  }

  /// Reads pending Android shares after startup or a warm share intent.
  /// Their provider grants are short-lived: finish all handles after import.
  /// The same serial SAF pipeline checks size, deduplication and format.
  Future<void> _consumeSharedBooks() async {
    final inbox = _sharedInbox;
    if (inbox == null || !mounted || _busy ||
        _recoveringInterruptedPick || _processingSharedBooks) return;
    _processingSharedBooks = true;
    try {
      while (mounted && !_busy && !_recoveringInterruptedPick) {
        final shared = await inbox.pending();
        if (!mounted || _busy || _recoveringInterruptedPick ||
            shared.isEmpty) break;
        try {
          await _import(
            recoveredBooks: [
              for (final item in shared)
                BatchPickedBook(
                  name: item.name,
                  pickedPath: null,
                  readAsByteStream: () => inbox.read(item.id),
                ),
            ],
            sharedFromAndroid: true,
          );
        } finally {
          await inbox.finish([for (final item in shared) item.id]);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not import shared Android books. '
              'Share the files again if needed.'),
        ));
      }
    } finally {
      _processingSharedBooks = false;
    }
  }

  /// The picker supports single and multi-file selection on Windows and
  /// Android SAF. Files are imported sequentially, with isolated per-file
  /// errors and no automatic audio or cloud requests.
  Future<void> _import({
    List<BatchPickedBook>? recoveredBooks,
    bool sharedFromAndroid = false,
  }) async {
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
      if (onlyBook != null && sharedFromAndroid) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Shared book imported into your library. '
              'Narration will not start automatically.'),
        ));
      } else if (onlyBook != null && recoveredBooks == null) {
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
      if (mounted && !_processingSharedBooks) {
        unawaited(_consumeSharedBooks());
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
                  Text('New collections: ${preview.collectionsToImport}'),
                  Text('Verified source bytes: '
                      '${(preview.verifiedBytes / (1024 * 1024))
                          .toStringAsFixed(1)} MiB'),
                  const SizedBox(height: 12),
                  const Text(
                    'Existing books, their positions, bookmarks and '
                    'settings will NOT be changed. New books regain '
                    'saved positions, bookmarks and catalog details. '
                    'Collection names from the backup are added when '
                    'missing, including empty collections; existing '
                    'collection assignments remain unchanged. '
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
              onPressed: preview.availableToImport == 0 &&
                      preview.collectionsToImport == 0
                  ? null : () => Navigator.pop(dialog, true),
              child: const Text('Restore library additions'),
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
            'Bookmarks restored: ${result.bookmarksImported}\n'
            'Collections added: ${result.collectionsImported}\n\n'
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

  Future<void> _open(BookRecord book, {
    LibraryFullTextJump? initialSearchJump,
  }) async {
    try {
      await widget.store.markBookOpened(book.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: book, store: widget.store,
            mediaHandler: widget.mediaHandler,
            initialSearchJump: initialSearchJump,
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

  Future<void> _manageCollections() async {
    await showManageBookCollections(
      context: context, store: widget.store,
    );
    if (!mounted) return;
    final exists = widget.store.collections.any(
        (item) => item.id == _collectionFilterId) ||
        widget.store.smartCollections.any(
        (item) => item.id == _collectionFilterId);
    setState(() {
      if (!exists) _collectionFilterId = null;
    });
  }

  Future<void> _assignCollections(BookRecord book) async {
    await showBookCollectionMembership(
      context: context, store: widget.store, bookId: book.id,
    );
    if (mounted) setState(() {});
  }

  void _toggleFavorite(BookRecord book) {
    try {
      widget.store.setBookFavorite(book.id, !book.isFavorite);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cannot update favorite: $error'),
        ));
      }
    }
  }

  void _setReadingStatus(BookRecord book, BookReadingStatus status) {
    try {
      widget.store.setBookReadingStatus(book.id, status);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cannot change reading shelf: $error'),
        ));
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

  Future<void> _showFullTextSearch() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LibraryFullTextSearchSheet(
        store: widget.store,
        onOpenBook: (book, jump) =>
            unawaited(_open(book, initialSearchJump: jump)),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showLibrarySearchHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Search library'),
        content: const Text(
          'Search is local and matches book titles, authors and series. '
          'Use multiple words to require all of them. Use double quotes '
          'for a phrase, for example "space opera". '
          'Use title:, author: or series: to restrict a term, for '
          'example author:"Ada Writer" series:Atlas. '
          'You can combine field terms with existing format, shelf, '
          'favorites and collection filters. The text inside books '
          'is not searched or uploaded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _openLibraryTools({bool autofocusSearch = false}) async {
    if (_busy) return;
    final selection = await showOrganizedActionSheet(
      context,
      title: 'Library tools',
      autofocusSearch: autofocusSearch,
      sections: const [
        OrganizedActionSection(title: 'Organize', items: [
          OrganizedActionItem(
            id: 'collections',
            icon: Icons.folder_open_outlined,
            title: 'Collections & smart shelves',
            subtitle: 'Organize books and saved filters',
          ),
        ]),
        OrganizedActionSection(title: 'Discover', items: [
          OrganizedActionItem(
            id: 'fulltext', icon: Icons.manage_search,
            title: 'Search inside books',
            subtitle: 'Find passages offline',
          ),
          OrganizedActionItem(
            id: 'statistics', icon: Icons.insights_outlined,
            title: 'Reading statistics',
            subtitle: 'Your reading history and progress',
          ),
        ]),
        OrganizedActionSection(title: 'Data & backups', items: [
          OrganizedActionItem(
            id: 'backup', icon: Icons.backup_outlined,
            title: 'Export private library backup',
            subtitle: 'Create a portable backup of your books',
          ),
          OrganizedActionItem(
            id: 'restore', icon: Icons.restore,
            title: 'Restore library backup',
            subtitle: 'Review a backup before restoring',
          ),
        ]),
        OrganizedActionSection(title: 'Help', items: [
          OrganizedActionItem(
            id: 'keyboard-help', icon: Icons.keyboard_outlined,
            title: 'Keyboard shortcuts',
            subtitle: 'Search, tools and import from the keyboard',
          ),
        ]),
      ],
    );
    if (!mounted || _busy || selection == null) return;
    switch (selection) {
      case 'collections':
        await _manageCollections();
        return;
      case 'fulltext':
        await _showFullTextSearch();
        return;
      case 'statistics':
        await _showReadingStatistics();
        return;
      case 'backup':
        await _exportBackup();
        return;
      case 'restore':
        await _restoreBackup();
        return;
      case 'keyboard-help':
        await showLibraryKeyboardHelp(context);
        return;
    }
  }

  Future<void> _showReadingStatistics() async {
    // Use every stored book, never the current filter selection.
    final stats = LibraryReadingStatistics.fromBooks(widget.store.books);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LibraryReadingStatisticsSheet(
        statistics: stats,
        store: widget.store,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allBooks = widget.store.books;
    final collections = widget.store.collections;
    final smartCollections = widget.store.smartCollections;
    final selectedCollection = collections.where(
        (item) => item.id == _collectionFilterId).toList();
    final selectedSmart = smartCollections.where(
        (item) => item.id == _collectionFilterId).toList();
    final filteredBookIds = selectedSmart.isNotEmpty
        ? widget.store.smartCollectionBookIds(selectedSmart.single.id)
        : selectedCollection.isNotEmpty
            ? widget.store.collectionBookIds(selectedCollection.single.id)
            : _collectionFilterId == null
                ? null : <String>{};
    final books = filterAndSortLibraryBooks(
      allBooks, query: _query, format: _formatFilter,
      activity: _activityFilter, sort: _sortOrder,
      favoritesOnly: _favoritesOnly,
      readingStatus: _readingStatusFilter,
      collectionBookIds: filteredBookIds,
    );
    final lastOpened = widget.store.lastOpenedBook;
    final interrupted = widget.store.interruptedNarrationBook;
    final compactLayout = MediaQuery.sizeOf(context).width < 600;
    final activeFilterCount =
        (_formatFilter != null ? 1 : 0) +
        (_readingStatusFilter != null ? 1 : 0) +
        (_collectionFilterId != null ? 1 : 0) +
        (_favoritesOnly ? 1 : 0) +
        (_activityFilter != LibraryActivityFilter.all ? 1 : 0) +
        (_sortOrder != LibrarySortOrder.recentlyImported ? 1 : 0);
    final filterControls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                              value: LibrarySortOrder.recentlyOpened,
                              child: Text('Recently opened')),
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
                            DropdownMenuItem(
                              value: LibrarySortOrder.favoritesFirst,
                              child: Text('Favorites first')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.readingStatus,
                              child: Text('Reading shelf')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _sortOrder = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Row(
                    children: [
                      const Text('Shelf'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<BookReadingStatus?>(
                          key: const ValueKey('library-reading-shelf-filter'),
                          isExpanded: true,
                          hint: const Text('All shelves'),
                          value: _readingStatusFilter,
                          items: [
                            const DropdownMenuItem<BookReadingStatus?>(
                              value: null, child: Text('All shelves')),
                            for (final status in BookReadingStatus.values)
                              DropdownMenuItem<BookReadingStatus?>(
                                value: status,
                                child: Text(status.label),
                              ),
                          ],
                          onChanged: (value) => setState(
                              () => _readingStatusFilter = value),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Row(
                    children: [
                      const Text('Collection'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<String?>(
                          key: const ValueKey('library-collection-filter'),
                          isExpanded: true,
                          value: selectedSmart.isNotEmpty
                              ? selectedSmart.single.id
                              : selectedCollection.isEmpty
                                  ? null : selectedCollection.single.id,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null, child: Text('All collections')),
                            for (final collection in collections)
                              DropdownMenuItem<String?>(
                                value: collection.id,
                                child: Text(collection.name),
                              ),
                            for (final smart in smartCollections)
                              DropdownMenuItem<String?>(
                                value: smart.id,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.auto_awesome_outlined,
                                        size: 16),
                                    const SizedBox(width: 8),
                                    Flexible(child: Text(smart.name)),
                                  ],
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(
                              () => _collectionFilterId = value),
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      FilterChip(
                        key: const ValueKey('library-favorites-only'),
                        avatar: const Icon(Icons.star, size: 18),
                        label: const Text('Favorites'),
                        selected: _favoritesOnly,
                        onSelected: (value) =>
                            setState(() => _favoritesOnly = value),
                      ),
                      const SizedBox(width: 8),
                      for (final activity in LibraryActivityFilter.values) ...[
                        ChoiceChip(
                          key: ValueKey('library-activity-${activity.name}'),
                          label: Text(switch (activity) {
                            LibraryActivityFilter.all => 'All activity',
                            LibraryActivityFilter.opened => 'Opened',
                            LibraryActivityFilter.neverOpened => 'Never opened',
                          }),
                          selected: _activityFilter == activity,
                          onSelected: (_) =>
                              setState(() => _activityFilter = activity),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
      ],
    );
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('EReader'),
            Text(
              '${allBooks.length} ${allBooks.length == 1 ? 'book' : 'books'} '
              'in library',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('library-import-action'),
            tooltip: 'Import book (Ctrl+O)',
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            key: const ValueKey('library-tools-menu'),
            tooltip: 'Library tools (Ctrl+K)',
            onPressed: _busy ? null : () => _openLibraryTools(),
            icon: const Icon(Icons.more_vert),
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
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const ValueKey('library-fulltext-open'),
                          tooltip: 'Search inside books offline',
                          onPressed: _busy ? null : _showFullTextSearch,
                          icon: const Icon(Icons.manage_search),
                        ),
                        TextButton.icon(
                          key: const ValueKey('library-stats-open'),
                          onPressed: _busy ? null : _showReadingStatistics,
                          icon: const Icon(Icons.insights_outlined),
                          label: const Text('Reading stats'),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: TextField(
                    key: const ValueKey('library-search'),
                    controller: _searchController,
                    focusNode: _librarySearchFocus,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      labelText: 'Search library',
                      hintText: 'title:Atlas author:"Ada Writer"',
                      errorText: LibrarySearchQuery.parse(_query).error,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Library search help',
                            icon: const Icon(Icons.help_outline),
                            onPressed: _showLibrarySearchHelp,
                          ),
                          if (_query.isNotEmpty)
                            IconButton(
                              tooltip: 'Clear library search',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (compactLayout)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const ValueKey('library-compact-filters'),
                            onPressed: () => setState(() =>
                                _smallFiltersExpanded = !_smallFiltersExpanded),
                            icon: Icon(_smallFiltersExpanded
                                ? Icons.expand_less : Icons.tune),
                            label: Text(activeFilterCount == 0
                                ? 'Filters & sort'
                                : 'Filters & sort ($activeFilterCount)'),
                          ),
                        ),
                        if (activeFilterCount > 0)
                          IconButton(
                            key: const ValueKey('library-reset-filters'),
                            tooltip: 'Reset library filters and sorting',
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.filter_alt_off_outlined),
                          ),
                      ],
                    ),
                  ),
                if (compactLayout)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          'Showing ${books.length} of ${allBooks.length} books',
                          key: const ValueKey('library-result-count'),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
                if (!compactLayout)
                  filterControls
                else if (_smallFiltersExpanded)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (MediaQuery.sizeOf(context).height * 0.40)
                          .clamp(130.0, 260.0).toDouble(),
                    ),
                    child: SingleChildScrollView(
                      key: const ValueKey('library-compact-filter-scroll'),
                      child: filterControls,
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
                        key: ValueKey('library-book-row-${book.id}'),
                        dense: compactLayout,
                        minVerticalPadding: 10,
                        leading: LibraryBookCover(
                          key: ValueKey('cover-tile-${book.id}'),
                          store: widget.store,
                          book: book,
                        ),
                        title: Text(book.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            semanticsLabel: book.title),
                        subtitle: Text(
                          [
                            if (book.author != null) book.author!,
                            if (book.series != null) book.series!,
                            if (book.language != null) book.language!,
                            book.format.name.toUpperCase(),
                            book.readingStatus.label,
                            'saved at character ${book.progressOffset}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          semanticsLabel: [
                            if (book.author != null) 'Author ${book.author}',
                            if (book.series != null) 'Series ${book.series}',
                            if (book.language != null) 'Language ${book.language}',
                            'Format ${book.format.name.toUpperCase()}',
                            'Shelf ${book.readingStatus.label}',
                            'Saved source position ${book.progressOffset}',
                          ].join(', '),
                        ),
                        onTap: _busy ? null : () => _open(book),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!compactLayout)
                              PopupMenuButton<BookReadingStatus>(
                              key: ValueKey('library-shelf-${book.id}'),
                              tooltip: 'Reading shelf: ${book.readingStatus.label}',
                              icon: const Icon(Icons.library_books_outlined),
                              enabled: !_busy,
                              initialValue: book.readingStatus,
                              onSelected: (status) =>
                                  _setReadingStatus(book, status),
                              itemBuilder: (_) => [
                                for (final status in BookReadingStatus.values)
                                  PopupMenuItem(
                                    value: status,
                                    child: Text(status.label),
                                  ),
                              ],
                            ),
                            IconButton(
                              key: ValueKey('library-favorite-${book.id}'),
                              icon: Icon(book.isFavorite
                                  ? Icons.star : Icons.star_border),
                              tooltip: book.isFavorite
                                  ? 'Remove from favorites'
                                  : 'Add to favorites',
                              onPressed: _busy
                                  ? null : () => _toggleFavorite(book),
                            ),
                            // Compact rows keep star and More as separate touch
                            // targets. Shelf commands move into More rather
                            // than squeezing the book title at phone widths.
                            PopupMenuButton<String>(
                              key: ValueKey('library-more-${book.id}'),
                              tooltip: 'More book actions',
                              enabled: !_busy,
                              icon: const Icon(Icons.more_vert),
                              onSelected: (action) {
                                if (action.startsWith('shelf:')) {
                                  _setReadingStatus(book,
                                      BookReadingStatus.values.byName(
                                          action.substring('shelf:'.length)));
                                } else if (action == 'edit') {
                                  unawaited(_editMetadata(book));
                                } else if (action == 'remove') {
                                  unawaited(_remove(book));
                                } else if (action == 'collections') {
                                  unawaited(_assignCollections(book));
                                }
                              },
                              itemBuilder: (_) => [
                                if (compactLayout)
                                  for (final status in BookReadingStatus.values)
                                    PopupMenuItem<String>(
                                      value: 'shelf:${status.name}',
                                      child: Row(
                                        children: [
                                          Icon(status == book.readingStatus
                                              ? Icons.check_circle
                                              : Icons.circle_outlined, size: 20),
                                          const SizedBox(width: 12),
                                          Text('Shelf: ${status.label}'),
                                        ],
                                      ),
                                    ),
                                const PopupMenuItem(
                                  value: 'collections',
                                  child: ListTile(
                                    leading: Icon(Icons.folder_outlined),
                                    title: Text('Book collections'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.edit_outlined),
                                    title: Text('Edit book details'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline),
                                    title: Text('Remove book'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
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
    if (!Platform.isWindows) {
      return _withLibraryKeyboard(scaffold, hasBooks: allBooks.isNotEmpty);
    }
    return _withLibraryKeyboard(DropTarget(
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
    ), hasBooks: allBooks.isNotEmpty);
  }

  Widget _withLibraryKeyboard(Widget content, {required bool hasBooks}) =>
      LibraryKeyboardShortcuts(
        onSearch: !_busy && hasBooks
            ? () => _librarySearchFocus.requestFocus()
            : null,
        onTools: _busy
            ? null
            : () => unawaited(_openLibraryTools(autofocusSearch: true)),
        onImport: _busy || _recoveringInterruptedPick
            ? null
            : () => unawaited(_import()),
        onHelp: () => unawaited(showLibraryKeyboardHelp(context)),
        child: content,
      );
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
