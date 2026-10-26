import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/openai_speech_engine.dart';
import '../../audio/speech_audio_cache.dart';
import '../../audio/secret_vault.dart';
import '../../audio/speech_engine_factory.dart';
import '../../data/library_store.dart';
import '../../domain/cloud_speech_consent.dart';
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
  bool _hasKey = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _current = widget.store.getSpeechPreferences(bookId: widget.bookId);
    _providerId = _current.providerId;
    _modelId = OpenAiSpeechEngine.supportedModels.contains(_current.modelId)
        ? _current.modelId
        : 'gpt-4o-mini-tts';
    _consent = widget.store.getConsent(
        widget.bookId, OpenAiSpeechEngine.providerId);
    if (_consent.maxCharacters > 0) {
      _quota.text = _consent.maxCharacters.toString();
    }
    _loadKeyStatus();
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
    try {
      if (!SpeechEngineFactory.availableProviders.contains(_providerId)) {
        throw const FormatException('Unknown provider');
      }
      final selected = _current.copyWith(
        providerId: _providerId,
        modelId: _modelId,
        clearVoice: _providerId != _current.providerId,
      );
      selected.validate();
      await widget.store.saveSpeechPreferences(
        selected, bookId: widget.bookId,
      );
      _current = selected;
      _feedback('Provider choice saved for this book.');
    } catch (error) {
      _feedback('Unable to save provider: ' + error.toString());
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
    _key.dispose();
    _quota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cloud = _providerId == OpenAiSpeechEngine.providerId;
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
            items: const [
              DropdownMenuItem(
                value: 'system', child: Text('Free system voices (offline)')),
              DropdownMenuItem(
                value: 'openai-speech',
                child: Text('OpenAI Audio Speech API (paid)')),
            ],
            onChanged: _busy ? null : (id) {
              if (id != null) setState(() => _providerId = id);
            },
          ),
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
            onPressed: _busy ? null : _saveProvider,
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
                helperText: 'This is NOT a spending limit in euros.',
              ),
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
          Text('Neural voices on this device',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Locally installed experimental models can be inspected or '
            'removed. They remain unavailable as speech providers until '
            'real Windows/Android native tests are completed.',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const OfflineVoiceManagerScreen(),
              ),
            ),
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
          const Text('System voices remain usable without keys, cloud '
              'consent, subscriptions or internet access.'),
        ],
      ),
    );
  }
}
