import 'package:ereader/audio/windows_speech_punctuation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const interpreter = WindowsSpeechPunctuation();

  List<String> words(String input) =>
      interpreter.plan(input).map((part) => part.text).toList();
  List<int> pauses(String input) =>
      interpreter.plan(input)
          .map((part) => part.pauseAfter.inMilliseconds).toList();

  test('Italian dialogue punctuation becomes pauses, not spoken symbols', () {
    const source = '«Ciao, Marco!» disse Anna. «Tutto bene?»';
    expect(words(source), [
      'Ciao', 'Marco', 'disse Anna', 'Tutto bene',
    ]);
    expect(pauses(source), [140, 420, 360, 420]);
    expect(source, contains('«'),
        reason: 'Original book and source anchors remain untouched');
  });

  test('literal full stops, commas, semicolons and question marks split',
      () {
    const source = 'Uno; due: tre, quattro... cinque! Sei?';
    expect(words(source), [
      'Uno', 'due', 'tre', 'quattro', 'cinque', 'Sei',
    ]);
    expect(pauses(source), [260, 260, 140, 360, 420, 420]);
  });

  test('unpunctuated Italian dialogue stays distinct from speech tags', () {
    const source = '«Vieni» disse Elena. «Arrivo» rispose Marco.';
    expect(words(source),
        ['Vieni', 'disse Elena', 'Arrivo', 'rispose Marco']);
    expect(pauses(source), [140, 360, 140, 360]);
  });

  test('quoted speech with punctuation does not double its pause', () {
    const source = '“Vieni!” disse Elena. “Davvero?” chiese lui.';
    expect(words(source),
        ['Vieni', 'disse Elena', 'Davvero', 'chiese lui']);
    expect(pauses(source), [420, 360, 420, 360]);
  });

  test('speech separated by quotation marks is not concatenated', () {
    const source = 'Disse "seguimi" e si mosse.';
    expect(words(source), ['Disse', 'seguimi', 'e si mosse']);
    expect(pauses(source), [140, 140, 360]);
  });

  test('dialogue dashes and accented text preserve lexical content', () {
    const source = '— Buongiorno, Èlia.\n— Vieni qui… per favore!';
    expect(words(source), ['Buongiorno', 'Èlia', 'Vieni qui', 'per favore']);
    expect(pauses(source), [140, 360, 360, 420]);
  });

  test('single curly and guillemet dialogue separates incises', () {
    const source = '‘Vieni’ disse Anna. ‹Sì› rispose.';
    expect(words(source), ['Vieni', 'disse Anna', 'Sì', 'rispose']);
    expect(pauses(source), [140, 360, 140, 360]);
  });

  test('curly single quotes preserve apostrophes inside a word', () {
    const source = '‘L’amico d’Èlia’ disse. It’s true.';
    expect(words(source), ['L’amico d’Èlia', 'disse', 'It’s true']);
    expect(pauses(source), [140, 360, 360]);
  });

  test('nested quotes keep one audible outer turn without symbol names', () {
    const source = '«Disse ‘non posso’ adesso» ribatté.';
    expect(words(source),
        ['Disse', 'non posso', 'adesso', 'ribatté']);
    expect(pauses(source), [140, 140, 140, 360]);
  });

  test('single ASCII quotations do not affect word apostrophes', () {
    const source = "'Vieni' disse. L'amico resta.";
    expect(words(source), ['Vieni', 'disse', "L'amico resta"]);
    expect(pauses(source), [140, 360, 360]);
  });

  test('a completed last phrase carries its pause to next TTS segment',
      () {
    final carry = WindowsSpeechPauseCarry();
    expect(carry.take(), Duration.zero);
    carry.recordCompleted(interpreter.plan('“Vieni!”'));
    expect(carry.take(), const Duration(milliseconds: 420));
    expect(carry.take(), Duration.zero,
        reason: 'The terminal pause is consumed exactly once');

    carry.recordCompleted(interpreter.plan('‹Sì›'));
    expect(carry.take(), const Duration(milliseconds: 140));
    carry.recordCompleted(interpreter.plan('no trailing punctuation'));
    expect(carry.take(), Duration.zero);
  });

  test('Stop clears carried punctuation and empty plans cannot extend it',
      () {
    final carry = WindowsSpeechPauseCarry();
    carry.recordCompleted(interpreter.plan('Davvero?'));
    carry.clear();
    expect(carry.take(), Duration.zero,
        reason: 'A resumed or sought-to segment has no stale pause');
    carry.recordCompleted(interpreter.plan('Fine.'));
    carry.recordCompleted(interpreter.plan('«»!?'));
    expect(carry.take(), Duration.zero,
        reason: 'Only actually completed nonempty speech can leave a tail');
  });

  test('voice changes and terminal punctuation use maximum, not sum',
      () {
    final carry = WindowsSpeechPauseCarry();
    carry.recordCompleted(interpreter.plan('«Vieni!»'));
    expect(
      carry.takeForTurn(const Duration(milliseconds: 110)),
      const Duration(milliseconds: 420),
      reason: 'Never add a speaker gap onto an existing exclamation pause',
    );
    expect(carry.takeForTurn(const Duration(milliseconds: 110)),
        const Duration(milliseconds: 110),
        reason: 'Previously completed pause must be consumed exactly once');

    carry.recordCompleted(interpreter.plan('«Vieni»'));
    expect(carry.takeForTurn(const Duration(milliseconds: 350)),
        const Duration(milliseconds: 350),
        reason: 'A longer user-selected voice breath wins the maximum');
    expect(carry.take(), Duration.zero);
  });

  test('Stop clearing a pending punctuation breath does not erase settings',
      () {
    final carry = WindowsSpeechPauseCarry();
    carry.recordCompleted(interpreter.plan('Davvero?'));
    carry.clear();
    expect(carry.takeForTurn(const Duration(milliseconds: 110)),
        const Duration(milliseconds: 110));
    expect(carry.takeForTurn(Duration.zero), Duration.zero);
    expect(
      () => carry.takeForTurn(const Duration(milliseconds: -1)),
      throwsArgumentError,
    );
  });

  test('decimal punctuation, times and signed numerals remain meaningful',
      () {
    expect(words('3,14 e 1.000 alle 12:30. Debito -5,20 €.'),
        ['3,14 e 1.000 alle 12:30', 'Debito -5,20 €']);
    expect(words('Versione 2.4.8 funziona!'),
        ['Versione 2.4.8 funziona']);
  });

  test('apostrophes internal to words and compound hyphens remain intact',
      () {
    expect(words(
      "L'amico dell’uomo, don't stop. porta-a-porta."),
      ["L'amico dell’uomo", "don't stop", 'porta-a-porta']);
  });

  test('quotes, brackets, asterisks and bullets are not spoken verbatim',
      () {
    expect(words(
        '"Ciao" (Marco) [nota] {appendice} * • prima – seconda.'),
        ['Ciao', 'Marco nota appendice prima', 'seconda']);
    expect(pauses('"Ciao" (Marco) [nota] {appendice} * • prima – seconda.'),
        [140, 260, 360]);
  });

  test('Unicode emoji and accented text are never split or rewritten',
      () {
    expect(words('«È là, 🐉!» disse.'),
        ['È là', '🐉', 'disse']);
  });

  test('Italian and English title abbreviations do not break names', () {
    const source = 'Il Dott. Rossi incontrò Mr. Darcy. Poi uscirono.';
    expect(words(source), ['Il Dott Rossi incontrò Mr Darcy', 'Poi uscirono']);
    expect(pauses(source), [360, 360]);
  });

  test('author initials and dotted acronyms avoid unnatural full stops', () {
    expect(words('J. R. R. Tolkien scrisse. A. Manzoni anche.'),
        ['J R R Tolkien scrisse', 'A Manzoni anche']);
    expect(pauses('J. R. R. Tolkien scrisse. A. Manzoni anche.'),
        [360, 360]);
    expect(words('Gli U.S.A. hanno risposto.'),
        ['Gli U S A', 'hanno risposto']);
  });

  test('ordinary sentence boundaries and trailing titles remain pauses', () {
    expect(words('Una frase. Poi un’altra. Fine.'),
        ['Una frase', 'Poi un’altra', 'Fine']);
    expect(pauses('Una frase. Poi un’altra. Fine.'), [360, 360, 360]);
    expect(words('È arrivato il dott.'),
        ['È arrivato il dott']);
    expect(pauses('È arrivato il dott.'), [360]);
    // Only listed titles or isolated uppercase initials qualify.
    expect(words('Si vede la Stella. Marco guarda.'),
        ['Si vede la Stella', 'Marco guarda']);
  });

  test('punctuation planner agrees with segmenter on Unicode names', () {
    expect(words('La Dott. Émile parlò. Poi uscì.'),
        ['La Dott Émile parlò', 'Poi uscì']);
    expect(words('Mr. Darcy. Ancora.'), ['Mr Darcy', 'Ancora']);
  });

  test('empty or punctuation-only input produces no native utterance',
      () {
    expect(interpreter.plan(''), isEmpty);
    expect(interpreter.plan('«»!?, …; ( )'), isEmpty);
    expect(interpreter.plan('   \n \t '), isEmpty);
  });

  test('newlines become semantic breath pauses', () {
    expect(words('Capitolo primo\nAlla luce.\nRitorno'),
        ['Capitolo primo', 'Alla luce', 'Ritorno']);
    expect(pauses('Capitolo primo\nAlla luce.\nRitorno'),
        [260, 360, 0]);
  });

  test('pauses are bounded and the last phrase requires no extra suffix',
      () {
    expect(words('Un esempio senza punteggiatura'),
        ['Un esempio senza punteggiatura']);
    expect(pauses('Un esempio senza punteggiatura'), [0]);
    expect(interpreter.plan('Ciao, mondo').length, 2);
    expect(pauses('Ciao, mondo'), [140, 0]);
  });
}
