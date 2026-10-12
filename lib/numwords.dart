/// Spoken English numbers to digits: "three reels at two thousand five hundred" -> "3 reels at 2500".
/// Handles units, teens, tens, hundred, thousand, lakh, crore, million, billion, "and" inside a number and "point" decimals
/// ("one point five" -> 1.5). Text that is already digits is left alone, except that recognizers' grouped digits
/// ("8 000", "12 000") are joined.
String wordsToDigits(String input) {
  final tokens = RegExp(r"[A-Za-z']+|\d[\d,]*(?:\.\d+)?|[^\sA-Za-z\d]+|\s+").allMatches(input).map((m) => m[0]!).toList();
  final out = StringBuffer();
  var i = 0;
  while (i < tokens.length) {
    final t = tokens[i];
    if (_isNumberWord(t)) {
      final parsed = _parse(tokens, i);
      if (parsed != null) {
        out.write(parsed.$1);
        i = parsed.$2;
        continue;
      }
    }
    out.write(t);
    i++;
  }
  // "8 000" / "12 000" / "1 000 000" typed by a recognizer -> one number
  return out.toString().replaceAllMapped(RegExp(r'\b(\d{1,3})((?:[    ]000)+)\b'), (m) => m[1]! + m[2]!.replaceAll(RegExp(r'[    ]'), ''));
}

const _units = {
  'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
  'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
};
const _tens = {'twenty': 20, 'thirty': 30, 'forty': 40, 'fourty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90};
const _scales = {'thousand': 1000, 'lakh': 100000, 'lakhs': 100000, 'lac': 100000, 'lacs': 100000, 'million': 1000000, 'crore': 10000000, 'crores': 10000000, 'billion': 1000000000};

bool _isNumberWord(String w) {
  final l = w.toLowerCase();
  return _units.containsKey(l) || _tens.containsKey(l) || l == 'hundred' || _scales.containsKey(l);
}

bool _isSpace(String t) => t.trim().isEmpty;

enum _Kind { none, unit, teen, tens, hundred, scale }

/// Reads a number phrase starting at [start]; returns its digits and the index after it, or null if it isn't one.
/// Words join into one number only where English does: "twenty one", "one hundred and five", "two thousand five hundred";
/// "three four" or "five twenty" are separate numbers.
(String, int)? _parse(List<String> tk, int start) {
  var total = 0, current = 0;
  var kind = _Kind.none;
  var i = start, consumed = start;
  while (i < tk.length) {
    final t = tk[i];
    if (_isSpace(t)) {
      i++;
      continue;
    }
    final l = t.toLowerCase();
    _Kind? next;
    if (_units.containsKey(l)) {
      final v = _units[l]!;
      if (v >= 10) {
        if (kind == _Kind.none || kind == _Kind.hundred || kind == _Kind.scale) {
          current += v;
          next = _Kind.teen;
        }
      } else if (kind == _Kind.none || kind == _Kind.tens || kind == _Kind.hundred || kind == _Kind.scale) {
        if (!(v == 0 && kind != _Kind.none)) {
          current += v;
          next = _Kind.unit;
        }
      }
    } else if (_tens.containsKey(l)) {
      if (kind == _Kind.none || kind == _Kind.hundred || kind == _Kind.scale) {
        current += _tens[l]!;
        next = _Kind.tens;
      }
    } else if (l == 'hundred') {
      if (kind == _Kind.none || kind == _Kind.unit || kind == _Kind.teen || kind == _Kind.tens) {
        current = (current == 0 ? 1 : current) * 100;
        next = _Kind.hundred;
      }
    } else if (_scales.containsKey(l)) {
      if (kind != _Kind.scale) {
        total += (current == 0 ? 1 : current) * _scales[l]!;
        current = 0;
        next = _Kind.scale;
      }
    } else if (l == 'and' && (kind == _Kind.hundred || kind == _Kind.scale) && _nextIsNumber(tk, i + 1)) {
      i++;
      continue;
    }
    if (next == null) break;
    kind = next;
    consumed = ++i;
  }
  if (kind == _Kind.none) return null;
  var value = (total + current).toString();
  // "one point five"
  var j = consumed;
  while (j < tk.length && _isSpace(tk[j])) {
    j++;
  }
  if (j < tk.length && tk[j].toLowerCase() == 'point') {
    final digits = StringBuffer();
    var k = j + 1;
    var end = consumed;
    while (k < tk.length) {
      if (_isSpace(tk[k])) {
        k++;
        continue;
      }
      final d = _units[tk[k].toLowerCase()];
      if (d == null || d > 9) break;
      digits.write(d);
      end = ++k;
    }
    if (digits.isNotEmpty) {
      value = '$value.$digits';
      consumed = end;
      // "one point five lakh" -> 150000
      var n = consumed;
      while (n < tk.length && _isSpace(tk[n])) {
        n++;
      }
      final scale = n < tk.length ? _scales[tk[n].toLowerCase()] : null;
      if (scale != null) {
        final v = double.parse(value) * scale;
        value = v == v.roundToDouble() ? v.round().toString() : v.toString();
        consumed = n + 1;
      }
    }
  }
  return (value, consumed);
}

bool _nextIsNumber(List<String> tk, int from) {
  for (var i = from; i < tk.length; i++) {
    if (_isSpace(tk[i])) continue;
    return _isNumberWord(tk[i]);
  }
  return false;
}
