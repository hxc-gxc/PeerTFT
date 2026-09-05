import 'dart:math';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('CodeGenerator', () {
    test('generates the configured number of hyphen-separated words', () {
      const generator = CodeGenerator(wordCount: 4);
      final code = generator.generate();
      expect(code.split('-'), hasLength(4));
      expect(generator.isWellFormed(code), isTrue);
    });

    test('is deterministic given a seeded Random', () {
      final a = CodeGenerator(random: Random(42)).generate();
      final b = CodeGenerator(random: Random(42)).generate();
      expect(a, b);
    });

    test('rejects malformed codes', () {
      const generator = CodeGenerator();
      expect(generator.isWellFormed(''), isFalse);
      expect(generator.isWellFormed('renard'), isFalse);
      expect(generator.isWellFormed('renard-BUREAU-lampe'), isFalse);
      expect(generator.isWellFormed('renard--lampe'), isFalse);
      expect(generator.isWellFormed('a' * 200), isFalse);
    });

    test('accepts a well-formed code regardless of wordlist membership', () {
      const generator = CodeGenerator();
      expect(
        generator.isWellFormed('motaleatoire-inconnu-du-dictionnaire'),
        isTrue,
      );
    });
  });
}
