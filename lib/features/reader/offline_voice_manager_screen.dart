import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/offline_voice_pack.dart';
import '../../data/offline_voice_install_diagnostics.dart';
import '../../data/piper_paola_installer.dart';
import '../../data/curated_voice_staging.dart';
import '../../data/manual_voice_install_staging.dart';
import '../../audio/offline_voice_audition.dart';

/// Model management is deliberately separate from provider activation.
/// This screen lists verified on-device assets, can uninstall them and
/// optionally plays a user-confirmed local sample. Native FFI is initialized
/// ONLY after explicit preview approval. Choosing book voices remains separate.
class OfflineVoiceManagerScreen extends StatefulWidget {
  const OfflineVoiceManagerScreen({
    super.key,
    this.modelsDirectory,
    this.pickSourceDirectory,
    this.audition,
  });

  /// Injected in tests. Ordinary apps use private application support.
  final Future<Directory> Function()? modelsDirectory;

  /// Injects the picker in tests without loading Windows/Android plugins.
  final Future<String?> Function()? pickSourceDirectory;

  /// Optional injected sample service for tests (never touches native FFI).
  final OfflineVoiceAudition? audition;

  @override
  State<OfflineVoiceManagerScreen> createState() =>
      _OfflineVoiceManagerScreenState();
}

class _OfflineVoiceManagerScreenState
    extends State<OfflineVoiceManagerScreen> {
  List<OfflineVoicePackInspection> _packs = const [];
  String? _languageFilter;
  bool _loading = false;
  String? _busyId;
  String? _message;
  OfflineVoiceImportPreview? _importPreview;
  bool _licenseReviewed = false;
  int _paolaDownloadBytes = 0;
  int? _paolaTotalBytes;
  late final OfflineVoiceAudition _audition;
  String? _sampleId;
  bool _stoppingSample = false;
  bool _sampleCancelled = false;
  String? _preparingModelId;
  // Ephemeral, bounded comparison data; never stored or transmitted.
  final Map<String, OfflineVoicePreviewReport> _previewMeasurements = {};
  static const int _maxPreviewMeasurements = 12;
  ManualVoiceStagingHealth? _manualStageHealth;

  Future<Directory> _directory() async {
    final resolver = widget.modelsDirectory;
    if (resolver != null) return await resolver();
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'offline-voices'));
  }

  @override
  void initState() {
    super.initState();
    _audition = widget.audition ?? OfflineVoiceAudition(
      loadPack: (id) async => loadInstalledOfflineVoicePack(
        packId: id, modelsDirectory: await _directory(),
      ),
    );
    _audition.onPreparedModelChanged = () {
      if (mounted) setState(() {});
    };
    unawaited(_refresh());
  }

  @override
  void dispose() {
    // Dispose invalidates model verification and cancels any active preview.
    // The controller retains native WAV cleanup ownership until it settles.
    unawaited(_audition.dispose().catchError((Object _) {}));
    super.dispose();
  }

  void _rememberPreviewMeasurement(String packId) {
    final report = _audition.lastReport;
    if (!mounted || report == null || report.packId != packId) return;
    setState(() {
      _previewMeasurements.remove(packId);
      if (_previewMeasurements.length >= _maxPreviewMeasurements) {
        _previewMeasurements.remove(_previewMeasurements.keys.first);
      }
      _previewMeasurements[packId] = report;
    });
  }

  Future<void> _stopSample() async {
    if (_sampleId == null || _stoppingSample) return;
    final stoppedId = _sampleId!;
    setState(() {
      _stoppingSample = true;
      _sampleCancelled = true;
    });
    try {
      await _audition.stop();
      if (mounted) {
        setState(() => _message = _preparingModelId == stoppedId
            ? 'Silent ONNX model preparation cancelled.'
            : 'Offline voice sample stopped.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Native voice Stop was not confirmed. '
            'Do not begin another preview until audio has ended.');
      }
    } finally {
      _rememberPreviewMeasurement(stoppedId);
      if (mounted) setState(() => _stoppingSample = false);
    }
  }

  /// Consent-only, silent native model load: RAM is bounded by the
  /// underlying worker idle timer and a second 3-minute controller TTL.
  Future<void> _prewarmVoice(OfflineVoicePackInspection entry) async {
    if (!mounted || _loading || _busyId != null || !entry.ready ||
        entry.installed?.phonemizerDataDir == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Prepare offline voice model silently?'),
        content: const Text(
          'This re-verifies the installed local voice and loads ONNX '
          'into RAM without playing audio or generating any WAV. '
          'It may use substantial CPU and memory. Only one model can '
          'be prepared; it expires after at most 3 minutes and is '
          'released on Stop, removal or screen exit. '
          'The next Play rechecks SHA-256 before reuse. '
          'No book text, network or API credits are involved.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Prepare model')),
        ],
      ),
    );
    if (!mounted || approved != true || _busyId != null) return;
    setState(() {
      _busyId = entry.id;
      _sampleId = entry.id;
      _preparingModelId = entry.id;
      _sampleCancelled = false;
      _message = 'Verifying and loading the silent ONNX model...';
    });
    try {
      await _audition.prewarm(entry.id);
      if (mounted && !_sampleCancelled) {
        setState(() => _message =
            'Offline voice model prepared without audio. '
            'Next sample can reuse it for up to 3 minutes.');
      }
    } on UnsupportedError {
      if (mounted && !_sampleCancelled) {
        setState(() => _message =
            'This speech engine does not support silent ONNX preparation.');
      }
    } catch (_) {
      if (mounted && !_sampleCancelled) {
        setState(() => _message =
            'Silent model preparation failed or was cancelled. '
            'No WAV, text or cloud request was created.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _sampleId = null;
          _preparingModelId = null;
          _busyId = null;
        });
      }
    }
  }

  Future<void> _releasePreparedVoice() async {
    if (_loading || _busyId != null) return;
    try {
      await _audition.stop();
      if (mounted) {
        setState(() => _message =
            'Prepared offline model released from memory.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Unable to confirm prepared model release. Stop playback '
            'and restart the voice manager before retrying.');
      }
    }
  }

  Future<void> _previewVoice(OfflineVoicePackInspection entry,
      {bool compareColdWarm = false}) async {
    if (!mounted || _loading || _busyId != null || !entry.ready ||
        entry.installed?.phonemizerDataDir == null ||
        offlineVoiceSampleText(entry.installed!.manifest.locale) == null) {
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(compareColdWarm
            ? 'Compare cold and warm offline voice?'
            : 'Play experimental offline voice sample?'),
        content: Text(compareColdWarm
            ? 'This plays the same built-in demonstration phrase TWICE '
              'with one local model: first after a cold start, then with '
              'the worker still resident. Audio is audible both times. '
              'Stop cancels any remaining work. No book content, network '
              'calls, API credits or background warming are involved. '
              'Native Windows audio and memory use are experimental.'
            : 'This will speak a short, built-in demonstration phrase using '
              'your installed local model. It does not use your books, make '
              'cloud requests or spend API credits. Pause any current book '
              'narration first. Native Windows audio and Stop are still '
              'experimental; the model can use substantial CPU and RAM.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(compareColdWarm ? 'Play twice and compare'
                : 'Play sample'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true || _busyId != null) return;
    setState(() {
      _busyId = entry.id;
      _sampleId = entry.id;
      _sampleCancelled = false;
      _message = compareColdWarm
          ? 'Preparing cold/warm local voice comparison...'
          : 'Preparing a short local voice sample...';
    });
    try {
      await _audition.play(entry.id, compareColdWarm: compareColdWarm);
      if (mounted && !_sampleCancelled) {
        setState(() => _message = compareColdWarm
            ? 'Cold/warm comparison finished. Same short phrase was '
              'spoken twice; results are session-only.'
            : 'Local voice sample finished. '
              'This does not change the voice selected for any book.');
      }
    } catch (_) {
      // A native exception may include OS paths or model details.
      if (mounted) {
        setState(() => _message =
            'Offline sample failed. Verify the model, phonemizer and '
            'Windows audio output; no cloud fallback was used.');
      }
    } finally {
      _rememberPreviewMeasurement(entry.id);
      if (mounted) {
        setState(() {
          _sampleId = null;
          _busyId = null;
        });
      }
    }
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
      final preparedId = _audition.preparedModelId;
      if (preparedId != null &&
          !result.any((entry) =>
              entry.ready && entry.id == preparedId)) {
        // Release mapped ONNX files before presenting removed/corrupt state.
        await _audition.stop();
      }
      if (mounted) {
        setState(() {
          _packs = result;
          // A verified sample cannot be compared after its pack was
          // removed or replaced by an invalid model.
          final validIds = result
              .where((entry) => entry.ready)
              .map((entry) => entry.id).toSet();
          _previewMeasurements.removeWhere(
              (id, _) => !validIds.contains(id));
          if (_languageFilter != null &&
              !installedOfflineVoiceLanguages(result)
                  .contains(_languageFilter)) {
            _languageFilter = null;
          }
        });
      }
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

  /// Keep cached verification results for unchanged voices. Only the
  /// affected model is rehashed; explicit Refresh still checks all packs.
  /// Never claim a successful catalog update if filesystem access failed.
  Future<void> _reconcileChangedVoice(String packId) async {
    if (!mounted) return;
    try {
      final inspected = await inspectSingleOfflineVoicePack(
        packId: packId, modelsDirectory: await _directory(),
      );
      if ((inspected == null || !inspected.ready) &&
          _audition.hasPreparedModel(packId)) {
        await _audition.stop();
      }
      if (!mounted) return;
      setState(() {
        _packs = mergeOfflineVoicePackInspection(
            _packs, packId, inspected);
        if (inspected == null || !inspected.ready) {
          _previewMeasurements.remove(packId);
        }
        if (_languageFilter != null &&
            !installedOfflineVoiceLanguages(_packs)
                .contains(_languageFilter)) {
          _languageFilter = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            '${_message == null ? "" : "${_message!} "}'
            'Unable to update this model in the catalog. '
            'Use Refresh local voices to verify all installed models.');
      }
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
      if (_audition.hasPreparedModel(entry.id)) {
        // Windows may otherwise deny deletion of the memory-mapped ONNX.
        await _audition.stop();
      }
      final removed = await removeInstalledOfflineVoicePack(
        packId: entry.id,
        modelsDirectory: await _directory(),
      );
      if (!mounted) return;
      setState(() => _message = removed
          ? 'Local voice removed.'
          : 'This voice was already removed.');
    } catch (error) {
      if (mounted) {
        setState(() => _message = diagnoseOfflineVoiceFailure(
          error, operation: OfflineVoiceOperation.remove,
        ).message);
      }
    } finally {
      // Recheck even on failure: a partially removed model must not be
      // left marked verified, while other models need no expensive hashing.
      await _reconcileChangedVoice(entry.id);
      if (mounted) setState(() => _busyId = null);
    }
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
              ? await FilePicker.getDirectoryPath()
              : null;
      if (selected == null) return;
      final preview = await inspectOfflineVoiceImportFolder(
        sourceDirectory: Directory(selected),
      );
      if (mounted) {
        setState(() => _importPreview = preview);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = diagnoseOfflineVoiceFailure(
          error, operation: OfflineVoiceOperation.inspectFolder,
        ).message);
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
    } catch (error) {
      if (mounted) {
        setState(() => _message = diagnoseOfflineVoiceFailure(
          error, operation: OfflineVoiceOperation.installFolder,
        ).message);
      }
    } finally {
      await _reconcileChangedVoice(preview.manifest.id);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _installPiperPaola() async {
    if (!Platform.isWindows || _loading || _busyId != null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Install Paola — free Italian neural voice?'),
        content: const Text(
          'EReader will download about 67 MB from the official '
          'sherpa-onnx GitHub release, verify its pinned SHA-256, and '
          'install the converted Piper voice privately. No book text, '
          'API key or personal data is uploaded. The model repository '
          'declares MIT; the underlying voice dataset declares CC0; '
          'please review both licenses and the publisher. '
          'This Windows voice is EXPERIMENTAL: native audio, memory, '
          'Stop/Pause and performance have not been certified. '
          'You can switch back to system voices at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Download and verify'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _busyId = PiperPaolaCatalog.id;
      _message = null;
      _paolaDownloadBytes = 0;
      _paolaTotalBytes = null;
    });
    try {
      final root = await _directory();
      final installed = await installCuratedPiperPaola(
        modelsDirectory: root,
        stagingParent: Directory(
          p.join(root.parent.path, 'voice-downloads'),
        ),
        onProgress: (received, total) {
          // Incoming HTTPS chunks can be just a few KiB. Do not rebuild the
          // entire voice-manager page thousands of times during a download.
          if (mounted &&
              (received - _paolaDownloadBytes >= 512 * 1024 ||
                  (total != null && received >= total))) {
            setState(() {
              _paolaDownloadBytes = received;
              _paolaTotalBytes = total;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _message = '${installed.manifest.displayName} installed. '
              'Return to Speech engines and explicitly select '
              'Free local VITS / Piper to try it.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = diagnoseOfflineVoiceFailure(
          error, operation: OfflineVoiceOperation.installPaola,
        ).message);
      }
    } finally {
      await _reconcileChangedVoice(PiperPaolaCatalog.id);
      if (mounted) {
        setState(() {
          _busyId = null;
          _paolaDownloadBytes = 0;
          _paolaTotalBytes = null;
        });
      }
    }
  }

  /// On-demand, non-destructive preflight. This cannot change voice packs.
  Future<void> _inspectInterruptedManualImports() async {
    if (!mounted || _loading || _busyId != null) return;
    setState(() {
      _busyId = 'manual-import-staging-inspection';
      _manualStageHealth = null;
    });
    try {
      final result = await ManualVoiceInstallStaging.inspectAbandoned(
          await _directory());
      if (mounted) setState(() => _manualStageHealth = result);
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Unable to inspect temporary voice imports. '
            'No model files were changed.');
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Only marked, aged, unlocked local import stages qualify for deletion.
  /// The accepted installed voice directories never contain stage metadata.
  Future<void> _cleanInterruptedManualImports() async {
    if (!mounted || _loading || _busyId != null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Clean interrupted local voice imports?'),
        content: const Text(
          'Only EReader-marked incomplete manual model imports older '
          'than 24 hours will be checked. Active imports, installed '
          'models, unmarked legacy folders, your books and source voice '
          'folders remain untouched. Nothing is downloaded.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Clean old imports')),
        ],
      ),
    );
    if (!mounted || approved != true || _busyId != null) return;
    setState(() {
      _busyId = 'manual-import-staging-cleanup';
      _manualStageHealth = null;
      _message = 'Checking interrupted model imports...';
    });
    try {
      final cleaned = await ManualVoiceInstallStaging.recoverAbandoned(
          await _directory());
      if (mounted) {
        setState(() => _message = cleaned == 0
            ? 'No eligible interrupted local imports were removed.'
            : 'Removed $cleaned interrupted local model import(s).');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Unable to clean interrupted model imports. '
            'Installed voices and source folders were not modified.');
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Explicit, age-limited cleanup. No user document folders, installed
  /// model packs, active downloads or unmarked legacy files are touched.
  Future<void> _cleanInterruptedPaolaDownloads() async {
    if (!Platform.isWindows || _loading || _busyId != null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Clean interrupted voice downloads?'),
        content: const Text(
          'Only EReader-marked Paola download sessions older than '
          '24 hours will be considered. Active downloads, installed '
          'voice models, unrelated folders and unmarked files are '
          'excluded. This runs locally without network requests.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Clean old downloads')),
        ],
      ),
    );
    if (approved != true || !mounted || _busyId != null) return;
    setState(() {
      _busyId = 'paola-staging-cleanup';
      _message = 'Checking for abandoned voice downloads...';
    });
    try {
      final root = await _directory();
      final cleaned = await CuratedVoiceStaging.recoverAbandoned(
        Directory(p.join(root.parent.path, 'voice-downloads')),
      );
      if (mounted) {
        setState(() => _message = cleaned == 0
            ? 'No eligible abandoned Paola downloads were removed.'
            : 'Removed $cleaned abandoned Paola download session(s).');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Unable to clean old voice downloads. Other files were left alone.');
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
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
        if (Platform.isWindows) ...[
          FilledButton.icon(
            key: const ValueKey('install-piper-paola'),
            onPressed: _loading || _busyId != null
                ? null : _installPiperPaola,
            icon: const Icon(Icons.record_voice_over_outlined),
            label: const Text('Install Paola — Italian neural voice (free)'),
          ),
          const SizedBox(height: 6),
          const Text('About 67 MB. Official sherpa-onnx archive; verified '
              'SHA-256; works offline after installation. '
              'Experimental Windows playback only.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('clean-paola-downloads'),
            onPressed: _loading || _busyId != null
                ? null : _cleanInterruptedPaolaDownloads,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clean interrupted voice downloads'),
          ),
          const Text('Manual cleanup scans only marked Paola download '
              'sessions older than 24 hours. It never scans your books, '
              'installed models, or unmarked directories.'),
          if (_busyId == PiperPaolaCatalog.id) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _paolaTotalBytes == null ||
                      _paolaTotalBytes == 0
                  ? null
                  : (_paolaDownloadBytes / _paolaTotalBytes!).clamp(0.0, 1.0),
            ),
            Text('Downloaded '
                '${(_paolaDownloadBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                '${_paolaTotalBytes == null ? "" :
                    " / ${(_paolaTotalBytes! / (1024 * 1024)).toStringAsFixed(1)} MB"}'),
          ],
        ],
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
        if (Platform.isWindows || widget.modelsDirectory != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('inspect-manual-model-imports'),
            onPressed: _loading || _busyId != null
                ? null : _inspectInterruptedManualImports,
            icon: const Icon(Icons.info_outline),
            label: const Text('Inspect interrupted local imports'),
          ),
          if (_manualStageHealth != null) ...[
            const SizedBox(height: 5),
            Text(
              'Temporary import diagnostics (read-only sample): '
              'eligible ' + _manualStageHealth!.eligible.toString() +
              ', recent ' + _manualStageHealth!.recent.toString() +
              ', in use/locked ' + _manualStageHealth!.busy.toString() +
              ', unrecognized ' +
              _manualStageHealth!.unrecognized.toString() +
              '. Inspected ' +
              _manualStageHealth!.examined.toString() + ' of ' +
              _manualStageHealth!.candidates.toString() +
              ' discovered candidates.' +
              (_manualStageHealth!.limited
                  ? ' Scan limited; repeat inspection for another batch.'
                  : ''),
              key: const ValueKey('manual-model-import-health'),
            ),
            const Text('Eligible is a snapshot, not a guarantee. '
                'Recent and unrecognized files are never deleted.'),
          ],
          OutlinedButton.icon(
            key: const ValueKey('clean-manual-model-imports'),
            onPressed: _loading || _busyId != null
                ? null : _cleanInterruptedManualImports,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clean interrupted local model imports'),
          ),
          const Text('Only marked import sessions older than 24 hours; '
              'installed voices, source folders and unmarked files are '
              'never included.'),
        ],
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
        if (_packs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Verified model files: '
            '${offlineVoiceSizeLabel(verifiedOfflineVoiceTotalBytes(_packs))} '
            'across ${_packs.where((entry) => entry.ready).length} installed '
            'voice(s). Damaged packs and temporary files are excluded.',
            key: const ValueKey('offline-model-storage-summary'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('offline-model-language-filter-${_languageFilter ?? 'all'}'),
            value: _languageFilter ?? 'all',
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Filter installed neural voices by language'),
            items: [
              const DropdownMenuItem(
                  value: 'all', child: Text('All languages')),
              for (final language in installedOfflineVoiceLanguages(_packs))
                DropdownMenuItem(
                    value: language, child: Text(language.toUpperCase())),
            ],
            onChanged: _loading || _busyId != null ? null : (value) {
              if (value == null) return;
              setState(() =>
                  _languageFilter = value == 'all' ? null : value);
            },
          ),
          const SizedBox(height: 6),
          const Text('Unavailable models remain visible as warnings, '
              'even while filtering verified voices.'),
          if (_languageFilter != null &&
              !filterInstalledOfflineVoicePacks(
                  _packs, _languageFilter).any((pack) => pack.ready))
            Text('No verified neural voices installed for '
                '${_languageFilter!.toUpperCase()}.'),
        ],
        for (final entry in filterInstalledOfflineVoicePacks(
            _packs, _languageFilter))
          Card(
            key: ValueKey('offline-voice-${entry.id}'),
            child: ListTile(
              leading: Icon(entry.ready
                  ? Icons.verified_outlined
                  : Icons.warning_amber_outlined),
              title: Text(entry.installed?.manifest.displayName ?? entry.id),
              subtitle: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.ready
                      ? 'Verified files · ${entry.installed!.manifest.locale} · '
                          '${entry.installed!.manifest.licenseId} · '
                          '${entry.verifiedDiskBytes == null ? "Size unavailable" :
                              offlineVoiceSizeLabel(entry.verifiedDiskBytes!)}'
                      : 'Unavailable: missing or damaged voice files'),
                  if (_previewMeasurements[entry.id] != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      formatOfflineVoicePreviewReport(
                          _previewMeasurements[entry.id]!),
                      key: ValueKey('offline-preview-metrics-${entry.id}'),
                    ),
                  ],
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((Platform.isWindows || widget.audition != null) &&
                      entry.ready &&
                      entry.installed?.phonemizerDataDir != null &&
                      offlineVoiceSampleText(
                          entry.installed!.manifest.locale) != null)
                    IconButton(
                      key: ValueKey('offline-voice-preview-${entry.id}'),
                      tooltip: _sampleId == entry.id
                          ? _preparingModelId == entry.id
                              ? 'Cancel model preparation ${entry.id}'
                              : 'Stop sample ${entry.id}'
                          : 'Preview voice ${entry.id}',
                      icon: Icon(_sampleId == entry.id
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline),
                      onPressed: _sampleId == entry.id
                          ? (_stoppingSample ? null : _stopSample)
                          : (_loading || _busyId != null
                              ? null : () => _previewVoice(entry)),
                    ),
                  if ((Platform.isWindows || widget.audition != null) &&
                      entry.ready &&
                      entry.installed?.phonemizerDataDir != null &&
                      offlineVoiceSampleText(
                          entry.installed!.manifest.locale) != null)
                    IconButton(
                      key: ValueKey('offline-voice-compare-${entry.id}'),
                      tooltip: 'Compare cold/warm ${entry.id} (plays twice)',
                      icon: const Icon(Icons.speed_outlined),
                      onPressed: _loading || _busyId != null
                          ? null : () => _previewVoice(
                              entry, compareColdWarm: true),
                    ),
                  if ((Platform.isWindows || widget.audition != null) &&
                      entry.ready &&
                      entry.installed?.phonemizerDataDir != null)
                    IconButton(
                      key: ValueKey('offline-voice-prewarm-${entry.id}'),
                      tooltip: _audition.hasPreparedModel(entry.id)
                          ? 'Release prepared model ${entry.id}'
                          : 'Prepare model silently ${entry.id}',
                      icon: Icon(_audition.hasPreparedModel(entry.id)
                          ? Icons.memory_outlined
                          : Icons.bolt_outlined),
                      onPressed: _loading || _busyId != null ? null
                          : _audition.hasPreparedModel(entry.id)
                              ? _releasePreparedVoice
                              : () => _prewarmVoice(entry),
                    ),
                  IconButton(
                    tooltip: 'Remove voice ${entry.id}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _loading || _busyId != null
                        ? null : () => _remove(entry),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Voice preview metrics are session-only, stored in memory '
          '(up to 12 voices). Verification measures SHA-256 reading; '
          'native synthesis excludes playback. Speech wall time '
          'includes synthesis, audio playback and cleanup. Decoder handoff '
          'is not acoustic onset. RAM is the whole app process, not the '
          'model alone. Stop includes native disposal. Cold/warm '
          'comparison plays the same public phrase twice on user consent; '
          'first/second wall times include playback and cannot be '
          'interpreted as native synthesis latency. Silent model '
          'preparation is opt-in and automatically expires after 3 '
          'minutes or on Stop; no WAV or audio is created.',
        ),
        const SizedBox(height: 8),
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
