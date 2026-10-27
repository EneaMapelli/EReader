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
        ['Ciao Marco nota appendice prima', 'seconda']);
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
