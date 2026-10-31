import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../../audio/openai_speech_engine.dart';
import '../../audio/speech_audio_cache.dart';
import '../../audio/secret_vault.dart';
import '../../audio/speech_engine_factory.dart';
import '../../audio/speech_engine.dart';
import '../../audio/system_voice_audition.dart';
import '../../audio/sherpa_vits_engine.dart';
import '../../data/offline_voice_pack.dart';
import '../../data/library_store.dart';
import '../../domain/cloud_speech_consent.dart';
import '../../domain/cloud_cost_estimate.dart';
import '../../domain/speech_preferences.dart';
import 'offline_voice_manager_screen.dart';

/// Model/provider selection is NOT consent. User separately approves sending
/// excerpts of this particular book to the selected external service.
class SpeechProviderScreen extends StatefulWidget {
  const SpeechProviderScreen({
    super.key,
    required this.store,
    required this.bookId,
    required this.vault,
  });

  final LibraryStore store;
  final String bookId;
  final SpeechSecretVault vault;

  @override
  State<SpeechProviderScreen> createState() => _SpeechProviderScreenState();
}

class _SpeechProviderScreenState extends State<SpeechProviderScreen> {
  late SpeechPreferences _current;
  late String _providerId;
  late String _modelId;
  late CloudSpeechConsent _consent;
  final _key = TextEditingController();
  final _quota = TextEditingController(text: '20000');
  // These prices are user-provided calculation inputs, never persisted as
  // a provider tariff, and are not treated as verified billing data.
  final _usdPerMillion = TextEditingController();
  final _usdBudget = TextEditingController();
  bool _hasKey = false;
  bool _busy = false;
  bool _checkingLocal = false;
  List<OfflineVoicePackInspection> _offlineChoices = const [];
  String? _selectedOfflineVoiceId;
  final SystemVoiceAudition _systemAudition = SystemVoiceAudition();
  List<SpeechVoice> _installedSystemVoices = const [];
  SpeechVoice? _selectedSystemVoice;
  String? _systemVoiceLanguageFilter;
  static const _automaticSystemVoice = '__auto_system_voice__';
  // Distinguish a deliberate draft "Automatic" from an unsaved old voice
  // when the OS voice catalog is refreshed.
  bool _explicitVoiceDraftChanged = false;
  bool _checkingSystem = false;
  bool _systemSamplePlaying = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _current = widget.store.getSpeechPreferences(bookId: widget.bookId);
    _providerId = _current.providerId;
    // Initially show voices for the book (or saved narrator's language).
    // The user can still switch to All languages or another accent.
    _systemVoiceLanguageFilter = systemVoicePrimaryLanguage(
        _current.voiceLocale ?? _current.language);
    if (_current.providerId == SherpaVitsSpeechEngine.providerId) {
      _selectedOfflineVoiceId = _current.modelId;
    }
    _modelId = OpenAiSpeechEngine.supportedModels.contains(_current.modelId)
        ? _current.modelId
        : 'gpt-4o-mini-tts';
    _consent = widget.store.getConsent(
        widget.bookId, OpenAiSpeechEngine.providerId);
    if (_consent.maxCharacters > 0) {
      _quota.text = _consent.maxCharacters.toString();
    }
    _loadKeyStatus();
    _inspectLocalVoices();
    // Inspect the OS voice catalog only when the user is considering
    // system TTS. Cloud/VITS settings must not initialize a native
    // audition engine or interrupt any unrelated platform audio.
    if (_providerId == 'system' || _providerId == 'system-native' ||
            _providerId == 'system-interpreted') {
      _inspectSystemVoices();
    }
  }

  Future<void> _inspectSystemVoices() async {
    if ((!Platform.isWindows && !Platform.isAndroid) ||
        (_providerId != 'system' && _providerId != 'system-native' &&
            _providerId != 'system-interpreted') ||
        _checkingSystem || _systemSamplePlaying) return;
    setState(() => _checkingSystem = true);
    try {
      final voices = await _systemAudition.listVoices();
      if (!mounted) return;
      final previousDraft = _selectedSystemVoice;
      final saved = resolveExplicitSystemVoice(
        voices,
        voiceName: previousDraft?.name ?? _current.voiceName,
        voiceLocale: previousDraft?.locale ?? _current.voiceLocale,
      );
      final languages = systemVoiceCatalogLanguages(voices);
      setState(() {
        _installedSystemVoices = voices;
        // Refreshing must not silently choose another narrator or replace
        // a pending reset to automatic with the old persisted voice.
        _selectedSystemVoice = _explicitVoiceDraftChanged
            ? resolveExplicitSystemVoice(voices,
                voiceName: previousDraft?.name,
                voiceLocale: previousDraft?.locale)
            : saved;
        if (_systemVoiceLanguageFilter != null &&
            !languages.contains(_systemVoiceLanguageFilter)) {
          _systemVoiceLanguageFilter = null;
        }
      });
    } catch (_) {
      _feedback('Unable to read installed system voices.');
    } finally {
      if (mounted) setState(() => _checkingSystem = false);
    }
  }

  Future<void> _stopSystemSample() async {
    try {
      await _systemAudition.stop();
    } catch (_) {
      _feedback('The system voice sample could not be stopped.');
    } finally {
      if (mounted) setState(() => _systemSamplePlaying = false);
    }
  }

  Future<void> _playSystemSample() async {
    final voice = _selectedSystemVoice;
    if (voice == null || _systemSamplePlaying ||
        _checkingSystem) return;
    setState(() => _systemSamplePlaying = true);
    try {
      await _systemAudition.play(
        voice,
        interpretWindowsPunctuation:
            _providerId == 'system-interpreted' ||
                (Platform.isWindows && _providerId == 'system'),
        rate: _current.rate,
        pitch: _current.pitch,
      );
    } catch (error) {
      _feedback('Could not preview this system voice: $error');
    } finally {
      if (mounted) setState(() => _systemSamplePlaying = false);
    }
  }

  Future<void> _inspectLocalVoices() async {
    if (!Platform.isWindows || _checkingLocal) return;
    setState(() => _checkingLocal = true);
    try {
      final support = await getApplicationSupportDirectory();
      final voices = await inspectOfflineVoicePacks(
        modelsDirectory: Directory(p.join(support.path, 'offline-voices')),
      );
      if (!mounted) return;
      setState(() {
        _offlineChoices = voices;
        final ready = voices.where((entry) => entry.ready &&
            entry.installed?.phonemizerDataDir != null).toList();
        if (!ready.any((entry) => entry.id == _selectedOfflineVoiceId)) {
          _selectedOfflineVoiceId = ready.isEmpty ? null : ready.first.id;
        }
      });
    } catch (_) {
      if (mounted) _feedback('Unable to check offline voice packs.');
    } finally {
      if (mounted) setState(() => _checkingLocal = false);
    }
  }

  Future<void> _loadKeyStatus() async {
    try {
      final key = await widget.vault.readKey(OpenAiSpeechEngine.providerId);
      if (mounted) setState(() => _hasKey = key?.isNotEmpty ?? false);
    } catch (error) {
      _feedback('Secure storage unavailable: ' + error.toString());
    }
  }

  void _feedback(String message) {
    if (mounted) setState(() => _message = message);
  }

  Future<void> _saveKey() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.vault.saveKey(
          OpenAiSpeechEngine.providerId, _key.text);
      _key.clear();
      await _loadKeyStatus();
      _feedback('API key saved in secure device storage.');
    } catch (error) {
      _feedback('Could not save key: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteKey() async {
    final approve = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete the OpenAI API key?'),
        content: const Text(
          'Cloud speech will stop until another API key is provided. '
          'Book files, settings and usage counters are unchanged.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (approve != true) return;
    await widget.vault.deleteKey(OpenAiSpeechEngine.providerId);
    if (mounted) {
      await _loadKeyStatus();
      _feedback('API key deleted.');
    }
  }

  Future<void> _saveProvider() async {
    if (_systemSamplePlaying) await _stopSystemSample();
    try {
      if (!SpeechEngineFactory.availableProviders.contains(_providerId)) {
        throw const FormatException('Unknown provider');
      }
      if (_providerId == 'system-native' && !Platform.isWindows) {
        throw const FormatException('Native punctuation comparison is Windows-only');
      }
      if (_providerId == SherpaVitsSpeechEngine.providerId) {
        if (!Platform.isWindows) {
          throw const FormatException('Offline neural trial is Windows-only');
        }
        final id = _selectedOfflineVoiceId;
        final matching = _offlineChoices.where((entry) => entry.id == id &&
            entry.ready && entry.installed?.phonemizerDataDir != null);
        if (id == null || matching.isEmpty) {
          throw const FormatException('Choose a verified VITS voice with phonemizer files');
        }
        final approved = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Try experimental local neural TTS?'),
            content: Text(
              'This is a free, offline VITS model trial using '
              '${matching.first.installed!.manifest.displayName}. '
              'The runtime has not passed manual Windows audio and Stop '
              'testing. Playback may fail, take time or use substantial '
              'CPU/RAM. No book text is uploaded or charged. You must '
              'review the model publisher and license yourself. '
              'Switch back to System voices if playback fails.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Keep system voice')),
              FilledButton(onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Try offline voice')),
            ],
          ),
        );
        if (approved != true || !mounted) return;
      }
      final modelForProvider =
          _providerId == SherpaVitsSpeechEngine.providerId
              ? _selectedOfflineVoiceId!
              : _providerId == OpenAiSpeechEngine.providerId
                  ? _modelId : 'gpt-4o-mini-tts';
      final offlineSelected = _providerId == SherpaVitsSpeechEngine.providerId
          ? _offlineChoices.firstWhere(
              (entry) => entry.id == modelForProvider).installed
          : null;
      final usingSystem =
          _providerId == 'system' || _providerId == 'system-native' ||
            _providerId == 'system-interpreted';
      final systemVoice = usingSystem ? _selectedSystemVoice : null;
      final selected = _current.copyWith(
        providerId: _providerId,
        modelId: modelForProvider,
        // Local VITS requires the exact model locale and has no
        // post-synthesis pitch support. Enforce these BEFORE persisting.
        language: offlineSelected?.manifest.locale ?? _current.language,
        pitch: offlineSelected == null ? _current.pitch : 1.0,
        voiceName: systemVoice?.name,
        voiceLocale: systemVoice?.locale,
        clearVoice: usingSystem
            ? systemVoice == null
            : (_providerId != _current.providerId ||
                (_providerId == SherpaVitsSpeechEngine.providerId &&
                    _current.modelId != modelForProvider)),
      );
      selected.validate();
      await widget.store.saveSpeechPreferences(
        selected, bookId: widget.bookId,
      );
      _current = selected;
      _explicitVoiceDraftChanged = false;
      _feedback('Provider choice saved for this book.');
    } catch (error) {
      _feedback('Unable to save provider: ' + error.toString());
    }
  }

  void _applyEstimatedCloudBudget() {
    try {
      final quote = CloudCostEstimate.fromUsdText(
        pricePerMillion: _usdPerMillion.text,
        totalBudget: _usdBudget.text,
      );
      final suggested = quote.characterLimit;
      if (suggested < 1) {
        throw const FormatException(
          'This USD budget cannot authorize even one character.',
        );
      }
      if (suggested < _consent.usedCharacters) {
        throw const FormatException(
          'Estimated limit is below already reserved characters. '
          'Previous cloud usage cannot be undone.',
        );
      }
      // Only update the *draft*. Consent and its database quota are
      // unchanged until the user reviews and confirms them below.
      setState(() => _quota.text = suggested.toString());
      _feedback('Draft set to $suggested characters '
          '(estimated USD ${quote.estimatedUsdForCharacters(suggested)} '
          'at the entered unit price). Review and save the character '
          'limit below to enforce it. Provider charges are not guaranteed.');
    } on FormatException catch (error) {
      _feedback('Invalid USD estimate: ${error.message}');
    }
  }

  Future<void> _enableCloud() async {
    if (_busy) return;
    final max = int.tryParse(_quota.text.trim());
    if (max == null || max < 1 || max > 10000000) {
      _feedback('Enter a character limit between 1 and 10,000,000.');
      return;
    }
    if (!_hasKey) {
      _feedback('Save your API key before enabling cloud narration.');
      return;
    }
    if (max < _consent.usedCharacters) {
      _feedback('The new limit cannot be less than the characters already used.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Allow cloud narration for this book?'),
        content: Text(
          'Individual passages of this book will be sent to OpenAI '
          'when you press Play. API charges may apply, including for '
          'requests that fail. EReader will reserve at most $max '
          'characters locally for this book, but this is not a monetary '
          'limit or a billing guarantee. Voice output may not reproduce '
          'every word exactly. No text will be sent merely by '
          'enabling this setting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep disabled'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Allow passages to be sent'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.store.configureCloudConsent(
        widget.bookId,
        OpenAiSpeechEngine.providerId,
        allowed: true,
        maxCharacters: max,
      );
      _consent = widget.store.getConsent(
          widget.bookId, OpenAiSpeechEngine.providerId);
      _feedback('Cloud narration permitted for this book only.');
    } catch (error) {
      _feedback('Cannot authorize cloud speech: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disableCloud() async {
    await widget.store.configureCloudConsent(
      widget.bookId,
      OpenAiSpeechEngine.providerId,
      allowed: false,
      maxCharacters: _consent.maxCharacters,
    );
    _consent = widget.store.getConsent(
        widget.bookId, OpenAiSpeechEngine.providerId);
    _feedback('Cloud narration disabled. Used-character history is retained.');
  }

  Future<void> _clearGeneratedAudio() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete generated audio for this book?'),
        content: const Text(
          'Generated speech files for this book will be removed '
          'from local private storage. Already consumed API usage '
          'cannot be refunded; replaying may generate new paid requests.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete cached audio'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PrivateMp3SpeechCache().clearBook(widget.bookId);
      _feedback('Generated audio for this book cleared.');
    } catch (error) {
      _feedback('Audio cache cleanup failed: ' + error.toString());
    }
  }

  @override
  void dispose() {
    unawaited(_systemAudition.dispose().catchError(
        (Object _, StackTrace __) {}));
    _key.dispose();
    _quota.dispose();
    _usdPerMillion.dispose();
    _usdBudget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cloud = _providerId == OpenAiSpeechEngine.providerId;
    final freeSystem =
        _providerId == 'system' || _providerId == 'system-native' ||
            _providerId == 'system-interpreted';
    final systemVoiceLanguages =
        systemVoiceCatalogLanguages(_installedSystemVoices);
    final filteredSystemVoices = filterSystemVoiceCatalog(
        _installedSystemVoices, _systemVoiceLanguageFilter);
    // The current draft remains visible while browsing another language,
    // so Flutter's dropdown always contains its selected value.
    final selectableSystemVoices = <SpeechVoice>[
      if (_selectedSystemVoice != null &&
          !filteredSystemVoices.any(
              (voice) => voice.key == _selectedSystemVoice!.key))
        _selectedSystemVoice!,
      ...filteredSystemVoices,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Speech engines')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Speech for this book',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _providerId,
            decoration: const InputDecoration(labelText: 'TTS protocol / engine'),
            items: [
              DropdownMenuItem(
                value: 'system',
                child: Text(Platform.isWindows
                     ? 'Free system voices — interpreted pauses'
                     : 'Free Android voices — native punctuation')),
              if (Platform.isAndroid ||
                  _providerId == 'system-interpreted')
                const DropdownMenuItem(
                  value: 'system-interpreted',
                  child: Text('Free system voices — interpreted punctuation (trial)')),
              if (Platform.isWindows)
                const DropdownMenuItem(
                  value: 'system-native',
                  child: Text('Free Windows voices — native punctuation')),
              if (Platform.isWindows &&
                  (_offlineChoices.any((item) =>
                      item.ready && item.installed?.phonemizerDataDir != null) ||
                   _providerId == SherpaVitsSpeechEngine.providerId))
                const DropdownMenuItem(
                  value: 'sherpa-vits',
                  child: Text('Free local VITS / Piper — experimental')),
              const DropdownMenuItem(
                value: 'openai-speech',
                child: Text('OpenAI Audio Speech API (paid)')),
            ],
            onChanged: _busy ? null : (id) async {
              if (id == null) return;
              if (_systemSamplePlaying) await _stopSystemSample();
              if (!mounted) return;
              setState(() => _providerId = id);
              if ((id == 'system' || id == 'system-native' ||
                   id == 'system-interpreted') &&
                  _installedSystemVoices.isEmpty) {
                await _inspectSystemVoices();
              }
            },
          ),
          if (freeSystem) ...[
            const SizedBox(height: 16),
            Text('Preview free installed voices',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('Hear a short built-in sample before saving a voice '
                'for this book. Samples use only the selected device TTS '
                'engine, not book passages or the OpenAI API. Some system '
                'voices may require services managed by your device.'),
            const SizedBox(height: 10),
            if (_checkingSystem) const LinearProgressIndicator(),
            if (_installedSystemVoices.isEmpty)
              const Text('No installed voices found. You can still save '
                  'the engine and use its device default voice. Check '
                  'Windows or Android settings to install more voices.'),
            DropdownButtonFormField<String>(
              key: ValueKey('voice-language-${systemVoiceLanguages.join(',')}-${_systemVoiceLanguageFilter ?? 'all'}'),
              // The first frame precedes asynchronous OS enumeration.
              // 'all' is always a valid dropdown item, including when
              // no installed voice has been discovered yet.
              value: systemVoiceLanguages.contains(_systemVoiceLanguageFilter)
                  ? _systemVoiceLanguageFilter : 'all',
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Show installed voices by language'),
              items: [
                const DropdownMenuItem(
                    value: 'all', child: Text('All installed languages')),
                for (final language in systemVoiceLanguages)
                  DropdownMenuItem(value: language,
                      child: Text(language.toUpperCase())),
              ],
              onChanged: _busy || _systemSamplePlaying ? null : (value) {
                if (value == null) return;
                setState(() => _systemVoiceLanguageFilter =
                    value == 'all' ? null : value);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              // Recreate the field when the draft changes externally
              // (Reset/Refresh), not merely when the user picks an item.
              key: ValueKey('system-voice-${_selectedSystemVoice?.key ?? _automaticSystemVoice}-${_systemVoiceLanguageFilter ?? 'all'}'),
              value: _selectedSystemVoice?.key ?? _automaticSystemVoice,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Narrator voice for this book'),
              items: [
                const DropdownMenuItem(
                  value: _automaticSystemVoice,
                  child: Text('Automatic — match book language')),
                for (final voice in selectableSystemVoices)
                  DropdownMenuItem(
                    value: voice.key,
                    child: Text(voice.toString(),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy || _systemSamplePlaying ? null : (key) {
                if (key == null) return;
                setState(() {
                  _explicitVoiceDraftChanged = true;
                  _selectedSystemVoice = key == _automaticSystemVoice
                      ? null
                      : selectableSystemVoices.firstWhere(
                          (voice) => voice.key == key);
                });
              },
            ),
            const SizedBox(height: 5),
            const Text('Automatic keeps the narrator unpinned and '
                'chooses an installed system voice compatible with the '
                'book language when available. Preview is available '
                'only for an explicitly selected voice.'),
            if (!_checkingSystem && _current.voiceName != null &&
                !_installedSystemVoices.any((voice) =>
                    voice.name == _current.voiceName &&
                    voice.locale == _current.voiceLocale))
              const Text('The previously saved voice is no longer '
                  'installed. Choose another one or save Automatic.'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _busy || _systemSamplePlaying ||
                        _checkingSystem || _selectedSystemVoice == null ||
                        systemVoiceSampleText(
                            _selectedSystemVoice!.locale) == null
                    ? null : _playSystemSample,
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Preview voice'),
              ),
              OutlinedButton.icon(
                onPressed: _systemSamplePlaying
                    ? _stopSystemSample : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop sample'),
              ),
              TextButton.icon(
                onPressed: _checkingSystem || _systemSamplePlaying
                    ? null : _inspectSystemVoices,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh voices'),
              ),
            ]),
            if (_selectedSystemVoice != null &&
                systemVoiceSampleText(
                    _selectedSystemVoice!.locale) == null)
              const Text('No fixed sample for this language yet; '
                  'the installed voice can still be selected and saved.'),
          ],
          if (_providerId == SherpaVitsSpeechEngine.providerId) ...[
            const SizedBox(height: 16),
            const Text(
              'Neural synthesis runs offline. Only manually installed '
              'and SHA-checked VITS packs with phonemizer data appear '
              'below. Piper voices must first be converted to the '
              'sherpa-onnx VITS package format (model.onnx, tokens.txt '
              'and espeak-ng-data). Audio compatibility is experimental.',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _offlineChoices.any((item) =>
                  item.id == _selectedOfflineVoiceId && item.ready &&
                  item.installed?.phonemizerDataDir != null)
                  ? _selectedOfflineVoiceId : null,
              decoration: const InputDecoration(
                  labelText: 'Installed offline voice'),
              items: [
                for (final entry in _offlineChoices)
                  if (entry.ready &&
                      entry.installed?.phonemizerDataDir != null)
                    DropdownMenuItem(
                      value: entry.id,
                      child: Text('${entry.installed!.manifest.displayName} '
                          '(${entry.installed!.manifest.locale})'),
                    ),
              ],
              onChanged: _busy ? null : (id) =>
                  setState(() => _selectedOfflineVoiceId = id),
            ),
            const SizedBox(height: 8),
          ],
          if (cloud) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _modelId,
              decoration: const InputDecoration(labelText: 'Speech model'),
              items: [
                for (final model in OpenAiSpeechEngine.supportedModels)
                  DropdownMenuItem(value: model, child: Text(model)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _modelId = value);
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'OpenAI reads short passages through its speech API. '
              'Cloud pitch adjustment and word-level timestamps are not '
              'provided by this adapter; playback speed is configurable. '
              'Speech may not be perfectly verbatim.',
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || _systemSamplePlaying
                ? null : _saveProvider,
            icon: const Icon(Icons.save),
            label: const Text('Save engine for this book'),
          ),
          if (cloud) ...[
            const Divider(height: 40),
            Text('Credentials',
                style: Theme.of(context).textTheme.titleLarge),
            Text(_hasKey
                ? 'An OpenAI API key is stored on this device.'
                : 'No OpenAI API key is stored.'),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'OpenAI API key',
                hintText: 'Paste your key (not displayed or logged)',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              FilledButton(
                onPressed: _busy ? null : _saveKey,
                child: const Text('Save key securely'),
              ),
              if (_hasKey)
                OutlinedButton(
                  onPressed: _busy ? null : _deleteKey,
                  child: const Text('Delete key'),
                ),
            ]),
            const Divider(height: 40),
            Text('Permission and usage limit',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_consent.allowed
                ? 'Cloud narration authorized for THIS book.'
                : 'Cloud narration is disabled for this book.'),
            Text('Characters reserved: ' + _consent.usedCharacters.toString()),
            Text('Characters remaining: ' +
                _consent.remainingCharacters.toString()),
            const SizedBox(height: 12),
            TextField(
              controller: _quota,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Hard character limit per book',
                helperText: 'Locally enforced before uncached API requests.',
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('Estimate a USD budget as characters'),
              subtitle: const Text('Optional calculator — no provider '
                  'price is fetched or stored'),
              childrenPadding: const EdgeInsets.only(bottom: 16),
              children: [
                const Text(
                  'Enter the current price for your exact speech model '
                  'in USD per 1,000,000 input characters, then a total '
                  'USD budget for this book. Verify the price with the '
                  'provider: model rates can change. This is only an '
                  'estimate, not a billing guarantee or a currency cap.',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _usdPerMillion,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'USD per 1 million characters',
                    hintText: 'e.g. 15.00 (check your current price)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _usdBudget,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'USD budget for this book',
                    hintText: 'e.g. 1.50',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _applyEstimatedCloudBudget,
                  child: const Text('Calculate draft character limit'),
                ),
                const Text(
                  'This fills the character-limit field only. It does '
                  'not grant consent or save changes. Use the separate '
                  'Review button below. Previous usage counts toward '
                  'the total; failed API requests may still be charged. '
                  'Actual billing can include other fees or rate changes.',
                ),
              ],
            ),
            Wrap(spacing: 8, children: [
              FilledButton.icon(
                onPressed: _busy ? null : _enableCloud,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(_consent.allowed
                    ? 'Update permitted character limit'
                    : 'Review and enable cloud narration'),
              ),
              if (_consent.allowed)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _disableCloud,
                  icon: const Icon(Icons.block),
                  label: const Text('Disable cloud narration'),
                ),
            ]),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!, style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
            )),
          ],
          const Divider(height: 40),
          Text('Other free voices on this device',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Windows and Android provide different free system voice '
            'catalogs. Select the exact installed voice in the reader. '
            'You can also install verified local neural VITS packs for '
            'an explicit Windows-only experimental trial. No automatic '
            'downloads, cloud bills or third-party voice services.',
          ),
          if (_checkingLocal) const LinearProgressIndicator(),
          if (Platform.isWindows)
            Text('Verified local neural packs: '
                '${_offlineChoices.where((item) => item.ready &&
                    item.installed?.phonemizerDataDir != null).length}'),
          const SizedBox(height: 12),
          Text('Other offline neural engines to evaluate',
              style: Theme.of(context).textTheme.titleMedium),
          const ListTile(
            dense: true,
            title: Text('Piper / VITS — Italian Paola, Riccardo'),
            subtitle: Text('Locally installed compatible sherpa-onnx '
                'VITS packs: optional experimental Windows playback.'),
          ),
          const ListTile(
            dense: true,
            title: Text('Kokoro 82M — Italian Sara, Nicola'),
            subtitle: Text('Free Apache-2.0 neural model. Not yet '
                'integrated; model and phonemizer adapter still required.'),
          ),
          const ListTile(
            dense: true,
            title: Text('Chatterbox Multilingual'),
            subtitle: Text('Free local neural model with Italian support. '
                'Not yet integrated; heavier runtime and tests required.'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const OfflineVoiceManagerScreen(),
                ),
              );
              if (mounted) await _inspectLocalVoices();
            },
            icon: const Icon(Icons.folder_outlined),
            label: const Text('Manage offline neural voices'),
          ),
          const Divider(height: 40),
          Text('Generated audio cache',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Generated audio is saved privately on this device (up to '
            '250 MiB across books). Cached audio for the same text, model '
            'and voice can be replayed without another paid API call. '
            'Deleting audio does not reset usage counters.',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _clearGeneratedAudio,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear generated audio for this book'),
          ),
          const SizedBox(height: 24),
          const Text('System voices and installed local VITS models run '
              'without API keys, cloud consent, subscriptions or internet. '
              'Experimental offline model quality is not guaranteed.'),
        ],
      ),
    );
  }
}
