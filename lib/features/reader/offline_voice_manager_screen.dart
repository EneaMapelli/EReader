import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/offline_voice_pack.dart';

/// Model management is deliberately separate from provider activation.
/// This screen lists verified on-device assets and can uninstall them,
/// but does not download binaries, initialize native FFI or select a voice.
class OfflineVoiceManagerScreen extends StatefulWidget {
  const OfflineVoiceManagerScreen({
    super.key,
    this.modelsDirectory,
    this.pickSourceDirectory,
  });

  /// Injected in tests. Ordinary apps use private application support.
  final Future<Directory> Function()? modelsDirectory;

  /// Injects the picker in tests without loading Windows/Android plugins.
  final Future<String?> Function()? pickSourceDirectory;

  @override
  State<OfflineVoiceManagerScreen> createState() =>
      _OfflineVoiceManagerScreenState();
}

class _OfflineVoiceManagerScreenState
    extends State<OfflineVoiceManagerScreen> {
  List<OfflineVoicePackInspection> _packs = const [];
  bool _loading = false;
  String? _busyId;
  String? _message;
  OfflineVoiceImportPreview? _importPreview;
  bool _licenseReviewed = false;

  Future<Directory> _directory() async {
    final resolver = widget.modelsDirectory;
    if (resolver != null) return await resolver();
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'offline-voices'));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh({bool clearMessage = true}) async {
    if (!mounted || _loading || _busyId != null) return;
    setState(() {
      _loading = true;
      if (clearMessage) _message = null;
    });
    try {
      final result = await inspectOfflineVoicePacks(
        modelsDirectory: await _directory(),
      );
      if (mounted) setState(() => _packs = result);
    } catch (_) {
      // Do not display local filesystem paths or native error stacks.
      if (mounted) {
        setState(() => _message =
            'Unable to check local voice models. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(OfflineVoicePackInspection entry) async {
    if (!mounted || _loading || _busyId != null) return;
    final approve = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove offline voice?'),
        content: Text(
          'Remove local model ${entry.id} and all of its voice files? '
          'This will not delete any books, saved positions, or cloud '
          'credentials. Removed models must be supplied again to reinstall.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove voice'),
          ),
        ],
      ),
    );
    if (approve != true || !mounted || _busyId != null) return;
    setState(() {
      _busyId = entry.id;
      _message = null;
    });
    try {
      final removed = await removeInstalledOfflineVoicePack(
        packId: entry.id,
        modelsDirectory: await _directory(),
      );
      if (!mounted) return;
      setState(() => _message = removed
          ? 'Local voice removed.'
          : 'This voice was already removed.');
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Unable to remove the voice. It may still be in use.');
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
    // Refresh after the mutation settles, regardless of removal result.
    await _refresh(clearMessage: false);
  }


  Future<void> _chooseImportFolder() async {
    if (!mounted || _loading || _busyId != null) return;
    setState(() {
      _loading = true;
      _importPreview = null;
      _licenseReviewed = false;
      _message = null;
    });
    try {
      final picker = widget.pickSourceDirectory;
      // A native filesystem path is required. Android SAF tree URIs are
      // not regular paths and must not be passed to dart:io.
      final selected = picker != null
          ? await picker()
          : Platform.isWindows
              ? await FilePicker.getDirectoryPath(
                  dialogTitle: 'Choose a local VITS voice pack folder',
                )
              : null;
      if (selected == null) return;
      final preview = await inspectOfflineVoiceImportFolder(
        sourceDirectory: Directory(selected),
      );
      if (mounted) {
        setState(() => _importPreview = preview);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Cannot inspect this voice folder. Check the pack manifest '
            'and required files.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _installSelectedFolder() async {
    final preview = _importPreview;
    if (!mounted || _loading || _busyId != null ||
        !_licenseReviewed || preview == null) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await installPreviewedOfflineVoicePack(
        preview: preview, modelsDirectory: await _directory(),
      );
      if (mounted) {
        setState(() {
          _importPreview = null;
          _licenseReviewed = false;
          _message = 'Local voice installed and SHA-checked. '
              'On Windows it can be selected under Speech engines as '
              'experimental offline VITS; real native audio is untested.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Voice installation rejected. Check the source files, '
            'checksums, space and existing model ID.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _refresh(clearMessage: false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Offline voice models'),
      actions: [
        IconButton(
          tooltip: 'Refresh local voices',
          onPressed: _loading || _busyId != null ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Experimental offline neural voices',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          Platform.isWindows
              ? 'Local VITS models are an experimental, opt-in Windows '
                  'speech option. You need sherpa-onnx-compatible assets '
                  'with an eSpeak phonemizer. File hashes do not prove '
                  'publisher identity or licensing. Stop/audio are untested.'
              : 'Neural playback is not yet enabled on Android. '
                  'Free system voices are available.',
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        if (Platform.isWindows || widget.pickSourceDirectory != null)
          OutlinedButton.icon(
            onPressed: _loading || _busyId != null
                ? null : _chooseImportFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Import local voice folder'),
          )
        else
          const Text(
            'Folder import currently requires a Windows filesystem '
            'path. Android SAF folder import needs a dedicated '
            'document-provider adapter; existing voices can still '
            'be inspected and removed here.',
          ),
        if (_importPreview != null) ...[
          const SizedBox(height: 12),
          Card(
            key: const ValueKey('offline-voice-import-preview'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Review offline voice before installation',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Name: ${_importPreview!.manifest.displayName}'),
                  Text('ID: ${_importPreview!.manifest.id}'),
                  Text('Language: ${_importPreview!.manifest.locale}'),
                  Text('Declared license: ${_importPreview!.manifest.licenseId}'),
                  Text('Files: ${(_importPreview!.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MiB'),
                  Text('Additional phonemizer files: '
                      '${_importPreview!.manifest.phonemizerResources.length}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Checksums in the local manifest are self-declared. '
                    'Review the publisher, license and expected hashes '
                    'independently. Files will be SHA-256 verified while '
                    'being copied after approval.',
                  ),
                  CheckboxListTile(
                    key: const ValueKey('offline-voice-license-approval'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _licenseReviewed,
                    onChanged: _loading ? null : (value) =>
                        setState(() => _licenseReviewed = value ?? false),
                    title: const Text(
                      'I checked the source and license of these files',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _loading || !_licenseReviewed
                        ? null : _installSelectedFolder,
                    icon: const Icon(Icons.download_done_outlined),
                    label: const Text('Verify and install locally'),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_loading) const LinearProgressIndicator(),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, key: const ValueKey('offline-voice-status')),
        ],
        if (!_loading && _packs.isEmpty) ...[
          const SizedBox(height: 12),
          const Text('No local neural voices installed.'),
        ],
        for (final entry in _packs)
          Card(
            key: ValueKey('offline-voice-${entry.id}'),
            child: ListTile(
              leading: Icon(entry.ready
                  ? Icons.verified_outlined
                  : Icons.warning_amber_outlined),
              title: Text(entry.installed?.manifest.displayName ?? entry.id),
              subtitle: Text(entry.ready
                  ? 'Verified files · ${entry.installed!.manifest.locale} · '
                      '${entry.installed!.manifest.licenseId}'
                  : 'Unavailable: missing or damaged voice files'),
              trailing: IconButton(
                tooltip: 'Remove voice ${entry.id}',
                icon: const Icon(Icons.delete_outline),
                onPressed: _loading || _busyId != null
                    ? null : () => _remove(entry),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Model checks use local SHA-256 hashes and may take time for '
          'large files. A checksum stored with a model is not proof of '
          'publisher identity or licensing. Downloads and playback '
          'requires separate consent before experimental Windows playback.',
        ),
      ],
    ),
  );
}
