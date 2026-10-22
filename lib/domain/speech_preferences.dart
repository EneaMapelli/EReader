/// Serializable voice and model selection, never contains credentials.
/// Provider IDs are application protocol identifiers, not user-supplied URLs.
class SpeechPreferences {
  const SpeechPreferences({
    this.providerId = 'system',
    this.modelId = 'gpt-4o-mini-tts',
    this.language = 'it-IT',
    this.rate = 0.5,
    this.pitch = 1.0,
    this.voiceName,
    this.voiceLocale,
  });

  final String providerId;
  final String modelId;
  final String language;
  final double rate;
  final double pitch;
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
        'voiceName': voiceName,
        'voiceLocale': voiceLocale,
      };

  factory SpeechPreferences.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported speech settings version');
    }
    final prefs = SpeechPreferences(
      providerId: json['providerId'] as String,
      modelId: json['modelId'] as String? ?? 'gpt-4o-mini-tts',
      language: json['language'] as String,
      rate: (json['rate'] as num).toDouble(),
      pitch: (json['pitch'] as num).toDouble(),
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
      voiceName: clearVoice ? null : (voiceName ?? this.voiceName),
      voiceLocale: clearVoice ? null : (voiceLocale ?? this.voiceLocale),
    );
    prefs.validate();
    return prefs;
  }
}
