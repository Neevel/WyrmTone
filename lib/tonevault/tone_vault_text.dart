/// Deterministic text handling for ToneVault search: normalization, phonetic
/// key and bounded edit distance. No locale dependency, no external package.
library;

abstract final class ToneText {
  static const _fold = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
    'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ı': 'i',
    'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o',
    'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ť': 't',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u',
    'ý': 'y', 'ÿ': 'y', 'ž': 'z', 'ź': 'z', 'ż': 'z',
    'ß': 'ss', 'æ': 'ae', 'œ': 'oe',
  };

  /// Lower-case, diacritics folded, apostrophes removed, everything that is not
  /// a letter or digit is one space, spaces collapsed and trimmed.
  /// "Guns N' Roses" -> "guns n roses", "AC/DC" -> "ac dc", "Ärger" -> "arger".
  static String normalize(String input) {
    final buffer = StringBuffer();
    var lastSpace = true;
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      if (ch == "'" || ch == '’' || ch == '‘' || ch == '`' || ch == '´') continue;
      final folded = _fold[ch] ?? ch;
      for (final c in folded.runes) {
        final isAlnum = (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7a);
        if (isAlnum) {
          buffer.writeCharCode(c);
          lastSpace = false;
        } else if (!lastSpace) {
          buffer.write(' ');
          lastSpace = true;
        }
      }
    }
    return buffer.toString().trim();
  }

  static List<String> tokens(String input) {
    final n = normalize(input);
    return n.isEmpty ? const [] : n.split(' ');
  }

  /// A cheap, deterministic sound-alike key: "metallica" and "metallika",
  /// "puppets" and "pupets" share one key. Numbers are kept as they are.
  static String phonetic(String token) {
    if (token.isEmpty || RegExp(r'\d').hasMatch(token)) return token;
    var s = token;
    s = s.replaceAll('ph', 'f').replaceAll('ck', 'k').replaceAll('th', 't').replaceAll('sch', 'sh').replaceAll('kh', 'k');
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      var c = s[i];
      final next = i + 1 < s.length ? s[i + 1] : '';
      if (c == 'c') {
        c = (next == 'e' || next == 'i' || next == 'y') ? 's' : 'k';
      } else if (c == 'q') {
        c = 'k';
      } else if (c == 'z') {
        c = 's';
      } else if (c == 'y') {
        c = 'i';
      } else if (c == 'x') {
        out.write('k');
        c = 's';
      }
      if (out.isNotEmpty && out.toString().endsWith(c)) continue; // collapse doubles
      out.write(c);
    }
    return out.toString();
  }

  /// Optimal-string-alignment distance (insert, delete, replace, adjacent swap),
  /// or [limit] + 1 as soon as it certainly exceeds [limit].
  static int distance(String a, String b, int limit) {
    if ((a.length - b.length).abs() > limit) return limit + 1;
    if (a == b) return 0;
    final n = a.length, m = b.length;
    var prev2 = List<int>.filled(m + 1, 0);
    var prev = List<int>.generate(m + 1, (j) => j);
    var cur = List<int>.filled(m + 1, 0);
    for (var i = 1; i <= n; i++) {
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= m; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j - 1] + cost;
        if (prev[j] + 1 < v) v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          if (prev2[j - 2] + 1 < v) v = prev2[j - 2] + 1;
        }
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > limit) return limit + 1;
      final t = prev2;
      prev2 = prev;
      prev = cur;
      cur = t;
    }
    return prev[m] > limit ? limit + 1 : prev[m];
  }
}
