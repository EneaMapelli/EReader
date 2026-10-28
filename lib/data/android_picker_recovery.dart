import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';

import 'batch_book_import.dart';

/// Native Android only, recovered once after the OS destroys the Activity
/// while an external file picker is open. Nothing is persisted in EReader
/// before validation and copying into the private library.
class InterruptedBookSelection {
  const InterruptedBookSelection({
    required this.selections,
    this.failed = false,
  });

  const InterruptedBookSelection.failure()
      : selections = const [],
        failed = true;

  final List<BatchPickedBook> selections;
  final bool failed;
}

/// May return only the *latest* outstanding Android pick. The native plugin
/// consumes its recovery payload once, so callers must never invoke this
/// on speculative screens or in a retry loop.
///
/// The native plugin, not this app, owns SAF permission grants. Reading each
/// file occurs immediately and serially via the usual 100 MB bounded adapter.
Future<InterruptedBookSelection?> recoverInterruptedAndroidBookPick() async {
  if (!Platform.isAndroid) return null;
  final picker = FilePickerPlatform.instance;
  if (picker is! FilePickerAndroid) return null;
  final lost = await picker.retrieveLostData();
  if (lost == null) return null;
  if (lost.exception != null) {
    return const InterruptedBookSelection.failure();
  }
  final files = lost.files;
  if (files == null || files.isEmpty) return null;
  return InterruptedBookSelection(
    selections: List<BatchPickedBook>.unmodifiable([
      for (final item in files)
        BatchPickedBook(
          name: item.name,
          pickedPath: item.path,
          readAsByteStream: item.readAsByteStream,
        ),
    ]),
  );
}
