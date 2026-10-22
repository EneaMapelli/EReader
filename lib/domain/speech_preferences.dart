/// Speech settings are local preferences; providerId is a stable protocol ID.
/// Only the 'system' speech engine is implemented in this milestone.
/// Cloud provider credentials are deliberately never stored in this model.
class SpeechPreferences {
  const SpeechPreferences({
    this.providerId = 'system',
    this.language = 'it-IT',
    this.rate = 0.5,
    this.pitch = 1.0,
    this.voiceName,
    this.voiceLocale,
  });

  final String providerId;
  final String language;
  final double rate;
  final double pitch;
  final String? voiceName;
  final String? voiceLocale;

  void validate() {
    if (providerId.isEmpty || providerId.length > 64) {
      throw const FormatException('Invalid TTS provider');
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
    if (voiceName != null && voiceName!.length > 200) {
      throw const FormatException('Invalid speech voice name');
    }
    if (voiceLocale != null && voiceLocale!.length > 40) {
      throw const FormatException('Invalid voice locale');
    }
  }

  Map<String, Object?> toJson() => {
        'version': 1,
        'providerId': providerId,
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
    String? language,
    double? rate,
    double? pitch,
    String? voiceName,
    String? voiceLocale,
    bool clearVoice = false,
  }) => SpeechPreferences(
        providerId: providerId ?? this.providerId,
        language: language ?? this.language,
        rate: rate ?? this.rate,
        pitch: pitch ?? this.pitch,
        voiceName: clearVoice ? null : (voiceName ?? this.voiceName),
        voiceLocale: clearVoice ? null : (voiceLocale ?? this.voiceLocale),
      );
}
