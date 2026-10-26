// PURE DART: no Flutter imports. How History search decides what matches.

/// Longest search text the app accepts.
const maxSearchLength = 100;

/// What the user typed in History's search box, ready to test rows against.
///
/// The text is split into words. A row matches when **every** word is found
/// in its note, its category name or its amount, so `coffee 4` finds coffee
/// purchases of 4.00 to 4.99. Case is ignored for every script (Bangla and
/// accented letters included).
class SearchQuery {
  SearchQuery._(this.terms, this._amountRanges);

  /// Lowercased words, without duplicates.
  final List<String> terms;

  /// For each term, the amounts in cents it stands for (null when the word is
  /// not a number).
  final List<(int, int)?> _amountRanges;

  factory SearchQuery.parse(String text) {
    final clipped = text.length > maxSearchLength
        ? text.substring(0, maxSearchLength)
        : text;
    final words = <String>[];
    for (final word in clipped.toLowerCase().split(RegExp(r'\s+'))) {
      if (word.isNotEmpty && !words.contains(word)) words.add(word);
    }
    return SearchQuery._(words, [for (final w in words) _amountRange(w)]);
  }

  bool get isEmpty => terms.isEmpty;

  /// Whether a transaction with these details matches every word.
  bool matches({
    required String category,
    required int amountCents,
    String? note,
  }) {
    if (isEmpty) return true;
    final categoryText = category.toLowerCase();
    final noteText = note?.toLowerCase() ?? '';
    for (var i = 0; i < terms.length; i++) {
      final term = terms[i];
      final range = _amountRanges[i];
      final inAmount =
          range != null && amountCents >= range.$1 && amountCents <= range.$2;
      if (!inAmount &&
          !categoryText.contains(term) &&
          !noteText.contains(term)) {
        return false;
      }
    }
    return true;
  }

  /// The parts of [text] to emphasise: `(start, end)` offsets, sorted and
  /// never overlapping. Empty when the text has no match, or when lowercasing
  /// changes its length (rare letters), in which case offsets could be wrong.
  List<(int, int)> highlights(String text) {
    if (isEmpty || text.isEmpty) return const [];
    final lower = text.toLowerCase();
    if (lower.length != text.length) return const [];
    final found = <(int, int)>[];
    for (final term in terms) {
      var from = 0;
      while (true) {
        final at = lower.indexOf(term, from);
        if (at < 0) break;
        found.add((at, at + term.length));
        from = at + term.length;
      }
    }
    if (found.isEmpty) return const [];
    found.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[found.first];
    for (final range in found.skip(1)) {
      final last = merged.last;
      if (range.$1 <= last.$2) {
        merged[merged.length - 1] = (
          last.$1,
          range.$2 > last.$2 ? range.$2 : last.$2,
        );
      } else {
        merged.add(range);
      }
    }
    return merged;
  }
}

/// The cents a typed number stands for, by prefix: `4` is 4.00 to 4.99,
/// `4.5` is 4.50 to 4.59 and `4.50` is exactly 4.50. A comma or dot both
/// work as the decimal mark, and `1,234` is read as a grouped thousand.
(int, int)? _amountRange(String word) {
  var w = word;
  if (RegExp(r'^\d{1,3}(,\d{3})+(\.\d{0,2})?$').hasMatch(w)) {
    w = w.replaceAll(',', '');
  }
  final m = RegExp(r'^(\d{1,9})(?:[.,](\d{0,2}))?$').firstMatch(w);
  if (m == null) return null;
  final whole = int.parse(m[1]!) * 100;
  final fraction = m[2] ?? '';
  switch (fraction.length) {
    case 0:
      return (whole, whole + 99);
    case 1:
      final base = whole + int.parse(fraction) * 10;
      return (base, base + 9);
    default:
      final exact = whole + int.parse(fraction);
      return (exact, exact);
  }
}
