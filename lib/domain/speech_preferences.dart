/// Uses only valid EPUB/catalog language tags. A bare language is mapped
/// to a deterministic, commonly supported speech locale; an explicit
/// region takes precedence. Unknown/malformed tags retain the system default
/// rather than passing arbitrary imported metadata to a native TTS engine.
/// This is a runtime default, NOT a persisted voice choice.
String? speechLocaleForBookMetadata(String? metadataLanguage) {
  if (metadataLanguage == null) return null;
  final value = metadataLanguage.trim().replaceAll('_', '-');
  final short = RegExp(r'^[a-zA-Z]{2,3}$');
  if (short.hasMatch(value)) {
    return const <String, String>{
      'it': 'it-IT',
      'en': 'en-US',
      'fr': 'fr-FR',
      'es': 'es-ES',
      'de': 'de-DE',
      'pt': 'pt-PT',
      'nl': 'nl-NL',
      'pl': 'pl-PL',
      'sv': 'sv-SE',
      'da': 'da-DK',
      'nb': 'nb-NO',
      'fi': 'fi-FI',
      'cs': 'cs-CZ',
      'tr': 'tr-TR',
      'ro': 'ro-RO',
      'ru': 'ru-RU',
      'uk': 'uk-UA',
      'ja': 'ja-JP',
      'ko': 'ko-KR',
      'zh': 'zh-CN',
      'ar': 'ar-SA',
      'hi': 'hi-IN',
    }[value.toLowerCase()];
  }
  final regional = RegExp(r'^([a-zA-Z]{2,3})-([a-zA-Z]{2}|[0-9]{3})$')
      .firstMatch(value);
  if (regional == null) return null;
  final language = regional.group(1)!.toLowerCase();
  final region = regional.group(2)!.toUpperCase();
  return '$language-$region';
}

/// Serializable voice and model selection, never contains credentials.
/// Provider IDs are application protocol identifiers, not user-supplied URLs.
class SpeechPreferences {
  const SpeechPreferences({
    this.providerId = 'system',
    this.modelId = 'gpt-4o-mini-tts',
    this.language = 'it-IT',
    this.rate = 0.5,
    this.pitch = 1.0,
    this.dialogueTurnPauseMs = 110,
    this.voiceName,
    this.voiceLocale,
  });

  final String providerId;
  final String modelId;
  final String language;
  final double rate;
  final double pitch;

  /// Extra breath between genuinely different installed system voices.
  /// Zero disables the transition pause. Stored as a value on the book or
  /// global speech profile; cloud/experimental neural TTS ignore it.
  final int dialogueTurnPauseMs;
  final String? voiceName;
  final String? voiceLocale;

  void validate() {
    if (!RegExp(r'^[a-z0-9-]{2,64}$').hasMatch(providerId)) {
      throw const FormatException('Invalid speech provider ID');
    }
    if (!RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(modelId)) {
      throw const FormatException('Invalid speech model ID');
    }
    if (language.isEmpty || language.length > 40) {
      throw const FormatException('Invalid speech language');
    }
    if (!rate.isFinite || rate < 0.2 || rate > 1.0) {
      throw const FormatException('Speech rate outside supported range');
    }
    if (!pitch.isFinite || pitch < 0.5 || pitch > 1.5) {
      throw const FormatException('Speech pitch outside supported range');
    }
    if (dialogueTurnPauseMs < 0 || dialogueTurnPauseMs > 2000) {
      throw const FormatException('System dialogue turn pause must be 0–2000 ms');
    }
    if (voiceName != null &&
        (voiceName!.isEmpty || voiceName!.length > 200)) {
      throw const FormatException('Invalid speech voice name');
    }
    if (voiceLocale != null && voiceLocale!.length > 40) {
      throw const FormatException('Invalid voice locale');
    }
    if ((voiceName == null) != (voiceLocale == null)) {
      throw const FormatException('Voice name and locale must be set together');
    }
  }

  Map<String, Object?> toJson() => {
        'version': 1,
        'providerId': providerId,
        'modelId': modelId,
        'language': language,
        'rate': rate,
        'pitch': pitch,
        'dialogueTurnPauseMs': dialogueTurnPauseMs,
        'voiceName': voiceName,
        'voiceLocale': voiceLocale,
      };

  factory SpeechPreferences.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported speech settings version');
    }
    final pauseValue = json['dialogueTurnPauseMs'];
    if (pauseValue != null && pauseValue is! int) {
      throw const FormatException('Invalid dialogue pause duration');
    }
    final prefs = SpeechPreferences(
      providerId: json['providerId'] as String,
      modelId: json['modelId'] as String? ?? 'gpt-4o-mini-tts',
      language: json['language'] as String,
      rate: (json['rate'] as num).toDouble(),
      pitch: (json['pitch'] as num).toDouble(),
      dialogueTurnPauseMs: pauseValue as int? ?? 110,
      voiceName: json['voiceName'] as String?,
      voiceLocale: json['voiceLocale'] as String?,
    );
    prefs.validate();
    return prefs;
  }

  SpeechPreferences copyWith({
    String? providerId,
    String? modelId,
    String? language,
    double? rate,
    double? pitch,
    int? dialogueTurnPauseMs,
    String? voiceName,
    String? voiceLocale,
    bool clearVoice = false,
  }) {
    final prefs = SpeechPreferences(
      providerId: providerId ?? this.providerId,
      modelId: modelId ?? this.modelId,
      language: language ?? this.language,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      dialogueTurnPauseMs: dialogueTurnPauseMs ?? this.dialogueTurnPauseMs,
      voiceName: clearVoice ? null : (voiceName ?? this.voiceName),
      voiceLocale: clearVoice ? null : (voiceLocale ?? this.voiceLocale),
    );
    prefs.validate();
    return prefs;
  }
}
