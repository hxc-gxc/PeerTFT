import 'dart:math';

import 'wordlist_fr.dart';

/// Generates and validates human-readable room codes, e.g.
/// `renard-bureau-lampe-zenith`.
///
/// The code is only ever used by the signaling server to match two clients
/// together; it is not the cryptographic secret used to derive the E2E
/// session key (see the architecture doc, section 4).
class CodeGenerator {
  const CodeGenerator({
    this.wordCount = 4,
    List<String> wordlist = frenchWordlist,
    Random? random,
  })  : _wordlist = wordlist,
        _providedRandom = random;

  // A const constructor's initializer list can only reference compile-time
  // constants, so the default secure RNG is resolved lazily via [_random]
  // instead of being baked into the initializer list.
  static final Random _secureRandom = Random.secure();

  final int wordCount;
  final List<String> _wordlist;
  final Random? _providedRandom;

  Random get _random => _providedRandom ?? _secureRandom;

  /// Draws [wordCount] words from the wordlist, with replacement, joined by
  /// `-`. Drawing with replacement keeps generation O(wordCount) and the
  /// birthday-bound collision risk is irrelevant here: codes are consumed
  /// within a short-lived room, not stored long-term.
  String generate() {
    final words = List.generate(
      wordCount,
      (_) => _wordlist[_random.nextInt(_wordlist.length)],
    );
    return words.join('-');
  }

  /// Whether [code] has the expected `word-word-...` shape. This does not
  /// check that every word belongs to the wordlist: the server must accept
  /// (and then fail to match) codes typed against an older/newer wordlist
  /// version without rejecting them outright as malformed.
  bool isWellFormed(String code) {
    if (code.isEmpty || code.length > 128) return false;
    final parts = code.split('-');
    if (parts.length < 2 || parts.length > 8) return false;
    return parts.every((part) => _wordPattern.hasMatch(part));
  }

  static final RegExp _wordPattern = RegExp(r'^[a-z]{2,32}$');
}
