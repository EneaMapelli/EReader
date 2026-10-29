import '../domain/speech_abbreviation.dart';

/// Windows system TTS input is not the displayed/source text.
///
/// Some Windows voices pronounce punctuation *names* literally. Instead of
/// hoping that a backend interprets every decorative symbol, prepare short
/// utterances with no standalone sentence/quote marks and pause between
/// them at the original source punctuation. This applies ONLY to the Windows
/// system-voice adapter: cloud and local VITS model inputs stay unchanged.
///
/// UTF-16 source positions / speech segments / anchors are NEVER changed.
/// The parts are speech-only and cannot be used as reading positions.
class WindowsSpeechPhrase {
  const WindowsSpeechPhrase(this.text, this.pauseAfter);

  final String text;
  final Duration pauseAfter;
}

class WindowsSpeechPunctuation {
  const WindowsSpeechPunctuation();

  static const shortPause = Duration(milliseconds: 140);
  static const mediumPause = Duration(milliseconds: 260);
  static const fullStopPause = Duration(milliseconds: 360);
  static const questionPause = Duration(milliseconds: 420);

  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _word = RegExp(r'[\p{L}\p{N}]', unicode: true);
  bool _withinWord(String source, int index) {
    if (index <= 0 || index + 1 >= source.length) return false;
    return _word.hasMatch(source.substring(index - 1, index)) &&
        _word.hasMatch(source.substring(index + 1, index + 2));
  }

  bool _betweenDigits(String text, int index) =>
      index > 0 && index + 1 < text.length &&
      _isDigit(text.codeUnitAt(index - 1)) &&
      _isDigit(text.codeUnitAt(index + 1));

  bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  /// A phrase may include word apostrophes, decimal punctuation and math
  /// operators: only *standalone punctuation* is consumed as narration
  /// boundary rather than pronounced as "comma"/"period"/"quote".
  List<WindowsSpeechPhrase> plan(String source) {
    if (source.isEmpty) return const [];
    final parts = <WindowsSpeechPhrase>[];
    final current = StringBuffer();

    void flush(Duration pause) {
      final cleaned = current.toString().replaceAll(_spaces, ' ').trim();
      current.clear();
      if (cleaned.isNotEmpty) {
        parts.add(WindowsSpeechPhrase(cleaned, pause));
      } else if (parts.isNotEmpty && pause > parts.last.pauseAfter) {
        final last = parts.removeLast();
        parts.add(WindowsSpeechPhrase(last.text, pause));
      }
    }

    for (var i = 0; i < source.length; i++) {
      final code = source.codeUnitAt(i);
      switch (code) {
        case 0x2c: // , decimal comma is spoken as part of a number
        case 0x2e: // . decimal point, thousands, versions
        case 0x3a: // : time of day
          if (_betweenDigits(source, i)) {
            current.writeCharCode(code);
          } else if (code == 0x2e &&
              isProtectedSpeechPeriod(source, i)) {
            // Do NOT send a literal period to Windows voices that may
            // speak "punto" aloud. Preserve lexical separation instead
            // of inserting a full-stop pause inside names/acronyms.
            current.write(' ');
          } else {
            flush(code == 0x2c ? shortPause
                : code == 0x3a ? mediumPause : fullStopPause);
          }
        case 0x3b: // ;
        case 0x2014: // em dash — (narrative pause)
        case 0x2013: // en dash – (narrative pause)
          flush(mediumPause);
        case 0x21: // !
        case 0x3f: // ?
          flush(questionPause);
        case 0x2026: // … (ellipsis)
          flush(fullStopPause);
        case 0x22: // " (plain paired quotations)
        case 0x00ab: // «
        case 0x00bb: // »
        case 0x201c: // “
        case 0x201d: // ”
        case 0x201e: // „
        case 0x201f: // ‟
          // Distinguish quoted speech from a following dialogue tag:
          // «Vieni» disse Elena must not become "Vieni disse Elena".
          // A short breath also separates a narrator's introductory tag
          // from quoted speech without adding words or changing source
          // offsets. Terminal !/?/. already carries the longer pause;
          // flush() preserves that maximum rather than double-pausing.
          flush(shortPause);
        case 0x28: // (
        case 0x29: // )
        case 0x5b: // [
        case 0x5d: // ]
        case 0x7b: // {
        case 0x7d: // }
          // Parentheses are not necessarily a speaker change. Preserve
          // word separation but avoid an artificial pause inside notes.
          current.write(' ');
        case 0x27: // straight apostrophe
        case 0x2019: // curly apostrophe in the middle of a word
          if (_withinWord(source, i)) {
            current.writeCharCode(code);
          } else {
            current.write(' ');
          }
        case 0x2d: // hyphen; leave internal compounds and negative numbers
          if (_withinWord(source, i) ||
              (i + 1 < source.length &&
                  _isDigit(source.codeUnitAt(i + 1)))) {
            current.write('-');
          } else {
            flush(shortPause);
          }
        case 0x0a: // new line from extracted page/paragraph
        case 0x0d:
          flush(mediumPause);
        case 0x2022: // bullet •
        case 0x25aa: // ▪
        case 0x25cf: // ●
        case 0x2a: // isolated asterisk / markdown decoration
          if (code == 0x2a && _withinWord(source, i)) {
            current.write('*'); // Preserve maths/code expression.
          } else {
            current.write(' ');
          }
        default:
          current.writeCharCode(code);
      }
    }
    flush(Duration.zero);
    return List<WindowsSpeechPhrase>.unmodifiable(parts);
  }
}
