import 'dart:async';
import 'dart:io';

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
  });

  /// Injected in tests. Ordinary apps use private application support.
  final Future<Directory> Function()? modelsDirectory;

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

  Future<Directory> _directory() async =>
      widget.modelsDirectory?.call() ??
      Directory(p.join((await getApplicationSupportDirectory()).path,
          'offline-voices'));

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_loading || _busyId != null) return;
    setState(() {
      _loading = true;
      _message = null;
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
    if (_loading || _busyId != null) return;
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
    await _refresh();
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
        const Text(
          'This screen checks voice files stored on this device. '
          'Neural synthesis is not yet enabled for reading: native '
          'Windows/Android tests and a licensed model catalog are still '
          'required. Free system voices remain available.',
        ),
        const SizedBox(height: 12),
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
          'are intentionally disabled until validation is complete.',
        ),
      ],
    ),
  );
}
