import 'package:flutter/foundation.dart';

import '../domain/speech_segment.dart';
import 'speech_engine.dart';

typedef SegmentStarted = Future<void> Function(SpeechSegment segment);

/// Serialized speech queue with session tokens to invalidate interrupted runs.
/// Pause stops the current native utterance; resume RESTARTS that segment.
/// Word-level timing and background sessions are not claimed in this milestone.
class ReaderPlayer extends ChangeNotifier {
  ReaderPlayer({
    required SpeechEngine engine,
    required List<SpeechSegment> segments,
    required this.onSegmentStarted,
    this.language = 'it-IT',
  }) : _engine = engine, _segments = segments;

  final SpeechEngine _engine;
  final List<SpeechSegment> _segments;
  final SegmentStarted onSegmentStarted;
  String language;
  double rate = 0.5;
  double pitch = 1.0;
  List<SpeechVoice> availableVoices = const [];
  SpeechVoice? selectedVoice;

  Future<void> loadVoices() async {
    try {
      availableVoices = await _engine.listVoices();
    } catch (_) {
      // Missing system TTS engine or unsupported voice enumeration.
      availableVoices = const [];
    }
    _notify();
  }

  Future<void> selectVoice(SpeechVoice voice) async {
    await pause();
    await _engine.chooseVoice(voice);
    selectedVoice = voice;
    language = voice.locale;
    _notify();
  }

  void setPitch(double value) {
    pitch = value;
    _notify();
  }

  int currentIndex = 0;
  bool isPlaying = false;
  int _session = 0;
  bool _disposed = false;

  List<SpeechSegment> get segments => _segments;
  bool get hasNext => currentIndex + 1 < _segments.length;

  void setRate(double value) {
    rate = value;
    _notify();
  }

  void setLanguage(String value) {
    language = value;
    _notify();
  }

  Future<void> play() async {
    if (isPlaying || _segments.isEmpty) return;
    if (currentIndex >= _segments.length) currentIndex = 0;
    final token = ++_session;
    isPlaying = true;
    _notify();
    try {
      while (token == _session && currentIndex < _segments.length) {
        final segment = _segments[currentIndex];
        await onSegmentStarted(segment);
        if (token != _session) return;
        await _engine.speak(segment.text, language: language, rate: rate, pitch: pitch);
        if (token != _session) return;
        currentIndex++;
        _notify();
      }
    } finally {
      if (token == _session) {
        isPlaying = false;
        _notify();
      }
    }
  }

  Future<void> pause() async {
    _session++;
    isPlaying = false;
    _notify();
    await _engine.stop();
  }

  Future<void> seekTo(int index) async {
    final restart = isPlaying;
    await pause();
    if (_segments.isEmpty) return;
    currentIndex = index.clamp(0, _segments.length - 1).toInt();
    _notify();
    if (restart) await play();
  }

  void _notify() { if (!_disposed) notifyListeners(); }

  @override
  void dispose() {
    _session++;
    _disposed = true;
    _engine.dispose();
    super.dispose();
  }
}
