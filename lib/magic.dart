import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'ai.dart';
import 'docs.dart';
import 'downloads.dart';
import 'models.dart';
import 'projects.dart';
import 'settings.dart';
import 'voice.dart';
import 'voice_pack.dart';
import 'voice_sherpa.dart';
import 'ui.dart';

// ---------------------------------------------------------------------------------------------------------------------
// Note parser (pure, no widgets). ponytail: one pass per line with regexes; the on-device model handles the messy cases.
// ---------------------------------------------------------------------------------------------------------------------

class ParsedItem {
  final String desc, unit, source, why;
  final double qty, rate;
  final int confidence;
  const ParsedItem({
    required this.desc,
    required this.qty,
    required this.rate,
    required this.unit,
    required this.confidence,
    required this.source,
    required this.why,
  });
  double get amount => qty * rate;
}

class ParsedNotes {
  final List<ParsedItem> items;
  final List<String> unparsed;
  final String? clientId, clientCandidate, title, terms;
  final double? tax, discountPct, discountFlat;
  const ParsedNotes(
    this.items,
    this.unparsed, {
    this.clientId,
    this.clientCandidate,
    this.title,
    this.terms,
    this.tax,
    this.discountPct,
    this.discountFlat,
  });
}

const _numP = r'\d+(?:,\d+)*(?:\.\d+)?';
const _sufP = r'(?:k|lakhs?|lacs?|lac|l)';
const _unitP = r'hours?|hrs?|h|days?|d|pcs?|pages?|pg|x|×';

String _sym(String cur) {
  final c = cur.trim();
  final extra = c.isEmpty ? '' : '|${RegExp.escape(c)}';
  return '(?:₹|\\\$|€|£|¥|rs\\.?|inr|usd|eur|gbp$extra)';
}

/// "1,20,000" -> 120000, "45" + "k" -> 45000, "1.5" + "L" -> 150000.
double parseAmount(String num, [String? suffix]) {
  final v = double.tryParse(num.replaceAll(',', '')) ?? 0;
  final s = (suffix ?? '').toLowerCase();
  if (s.isEmpty) return v;
  return s == 'k' ? v * 1000 : v * 100000;
}

String _unit(String? u) {
  final s = (u ?? 'x').toLowerCase();
  if (s.startsWith('h')) return 'h';
  if (s.startsWith('d')) return 'd';
  if (s.startsWith('pc')) return 'pcs';
  if (s.startsWith('p')) return 'pg';
  return 'x';
}

String _trimPunct(String s) => s
    .replaceAll(RegExp(r'^[\s,:\-–—=@|]+|[\s,:\-–—=@|]+$'), '')
    .replaceAll(RegExp(r'\s+'), ' ');
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
bool _hasWord(String s) => RegExp(r'[A-Za-zÀ-￿]').hasMatch(s);

ParsedNotes parseNotes(String text, List<Client> clients, String currency) {
  final sym = _sym(currency);
  final itemA = RegExp(
    '^(.*?)[\\s,:\\-–]*(\\d+(?:\\.\\d+)?)\\s*($_unitP)?\\s*(?:@|\\bat\\b)\\s*(?:$sym\\s*)?($_numP)($_sufP)?(?![\\w%])',
    caseSensitive: false,
  );
  final itemB = RegExp(
    '^(.*?)[\\s,:\\-–]*(\\d+(?:\\.\\d+)?)\\s*[x×]\\s*(?:$sym\\s*)?($_numP)($_sufP)?(?![\\w%])\\s*(?:each|ea|/\\w+)?\\s*\$',
    caseSensitive: false,
  );
  final token = RegExp(
    '(?<![\\w.,])(?:($sym)\\s*)?($_numP)($_sufP)?(?![\\w%])',
    caseSensitive: false,
  );

  final taxRes = [
    RegExp(
      r'\b(?:tax|gst|vat)\b\s*[:=@]?\s*(?:of\s+|at\s+)?(\d+(?:\.\d+)?)\s*%?',
      caseSensitive: false,
    ),
    RegExp(r'(\d+(?:\.\d+)?)\s*%\s*(?:tax|gst|vat)\b', caseSensitive: false),
  ];
  final noTaxRe = RegExp(
    r'\b(?:no|without|zero)\s+(?:tax|gst|vat)\b',
    caseSensitive: false,
  );
  final netRes = [
    RegExp(r'\bnet\s*(\d+)\b', caseSensitive: false),
    RegExp(
      r'\bdue\s+(?:in\s+|within\s+)?(\d+)\s*days?\b',
      caseSensitive: false,
    ),
  ];
  final receiptRe = RegExp(r'\bdue on receipt\b', caseSensitive: false);
  final discPctRes = [
    RegExp(r'(\d+(?:\.\d+)?)\s*%\s*(?:off|discount)\b', caseSensitive: false),
    RegExp(
      r'\bdiscount\b\s*[:=@]?\s*(?:of\s+)?(\d+(?:\.\d+)?)\s*%',
      caseSensitive: false,
    ),
  ];
  final discFlatRe = RegExp(
    '\\bdiscount\\b\\s*[:=@]?\\s*(?:of\\s+)?(?:$sym\\s*)?($_numP)($_sufP)?(?![\\w%])',
    caseSensitive: false,
  );
  final clientLineRe = RegExp(
    r'^(?:client|customer|bill(?:ed)?\s+to|for)\b\s*[:\-]?\s*(.+)$',
    caseSensitive: false,
  );
  final headerRe = RegExp(r'^(.+?)\s*[-–—:]\s*(.+)$');

  final items = <ParsedItem>[], unparsed = <String>[];
  double? tax, discPct, discFlat;
  String? terms, clientId, candidate, title;
  var content =
      0; // index among lines that aren't pure tax/terms/discount lines

  Client? matchClient(String l) {
    for (final c in clients) {
      if (c.name.trim().isNotEmpty &&
          RegExp(
            '\\b${RegExp.escape(c.name.trim())}\\b',
            caseSensitive: false,
          ).hasMatch(l)) {
        return c;
      }
    }
    for (final c in clients) {
      final w = c.name.trim().split(RegExp(r'\s+')).first;
      if (w.length >= 3 &&
          RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false).hasMatch(l)) {
        return c;
      }
    }
    return null;
  }

  String cut(String l, Match m) =>
      '${l.substring(0, m.start)} ${l.substring(m.end)}';

  for (final raw in text.split(RegExp(r'\n|;'))) {
    var l = raw.trim();
    if (l.isEmpty) continue;

    // tax / terms / discount fragments can share a line with each other ("tax 8%, net 14, 10% off")
    var meta = false;
    Match? m;
    if ((m = noTaxRe.firstMatch(l)) != null) {
      tax = 0;
      l = cut(l, m!);
      meta = true;
    } else {
      for (final re in taxRes) {
        if ((m = re.firstMatch(l)) != null) {
          tax = double.tryParse(m!.group(1)!);
          l = cut(l, m);
          meta = true;
          break;
        }
      }
    }
    for (final re in netRes) {
      if ((m = re.firstMatch(l)) != null) {
        terms = 'Net ${m!.group(1)}';
        l = cut(l, m);
        meta = true;
        break;
      }
    }
    if ((m = receiptRe.firstMatch(l)) != null) {
      terms = 'Due on receipt';
      l = cut(l, m!);
      meta = true;
    }
    for (final re in discPctRes) {
      if ((m = re.firstMatch(l)) != null) {
        discPct = double.tryParse(m!.group(1)!);
        l = cut(l, m);
        meta = true;
        break;
      }
    }
    if (discPct == null && (m = discFlatRe.firstMatch(l)) != null) {
      discFlat = parseAmount(m!.group(1)!, m.group(2));
      l = cut(l, m);
      meta = true;
    }
    l = _trimPunct(l);
    if (meta && !RegExp(r'[\w]').hasMatch(l)) continue;
    final lineNo = content++;

    ParsedItem? item;
    var mm = itemA.firstMatch(l) ?? itemB.firstMatch(l);
    if (mm != null) {
      final isA = mm.groupCount == 5;
      final desc = _trimPunct(mm.group(1) ?? '');
      final q = double.tryParse(mm.group(2)!) ?? 1;
      final unit = isA ? _unit(mm.group(3)) : 'x';
      final r = parseAmount(mm.group(isA ? 4 : 3)!, mm.group(isA ? 5 : 4));
      item = ParsedItem(
        desc: desc.isEmpty ? 'Line item' : desc,
        qty: q,
        rate: r,
        unit: unit,
        confidence: desc.isEmpty ? 71 : 96,
        source: l,
        why: 'Quantity, unit and rate all matched an explicit "qty @ rate" pattern.',
      );
    } else {
      final toks = token.allMatches(l).toList();
      final strong = toks
          .where((t) => t.group(1) != null || t.group(3) != null)
          .firstOrNull;
      if (strong != null) {
        final desc = _trimPunct(
          cut(l, strong).replaceAll(
            RegExp(r'\b(flat|fixed|total|only)\b', caseSensitive: false),
            ' ',
          ),
        );
        item = ParsedItem(
          desc: desc.isEmpty ? 'Line item' : desc,
          qty: 1,
          rate: parseAmount(strong.group(2)!, strong.group(3)),
          unit: 'x',
          confidence: 74,
          source: l,
          why: 'Found a flat price but no quantity. Assumed 1 unit. Confirm or adjust.',
        );
      }
    }
    if (item != null) {
      // "Acme - logo 8h @ 85": a known client in front of the description is the client, not part of the item
      final k = clientId == null ? matchClient(item.desc) : null;
      if (k != null) {
        clientId = k.id;
        final h = headerRe.firstMatch(item.desc);
        if (h != null) {
          item = ParsedItem(
            desc: _cap(_trimPunct(h.group(2)!)),
            qty: item.qty,
            rate: item.rate,
            unit: item.unit,
            confidence: item.confidence,
            source: item.source,
            why: item.why,
          );
        }
      }
      items.add(item);
      continue;
    }

    final known = matchClient(l);
    if (known != null) {
      clientId ??= known.id;
      if (title == null) {
        final h = headerRe.firstMatch(l);
        final rest = h != null
            ? h.group(2)!
            : _trimPunct(
                l.replaceAll(
                  RegExp(
                    '\\b${RegExp.escape(known.name.trim())}\\b',
                    caseSensitive: false,
                  ),
                  ' ',
                ),
              );
        if (_hasWord(rest)) title = _cap(_trimPunct(rest));
      }
      continue;
    }

    final cl = clientLineRe.firstMatch(l);
    if (cl != null && !RegExp(r'\d').hasMatch(cl.group(1)!)) {
      candidate ??= _trimPunct(cl.group(1)!);
      continue;
    }

    // bare trailing number with no currency: only believed when it is clearly a price (>= 10, not a year)
    final last = token.allMatches(l).lastOrNull;
    if (last != null) {
      final v = parseAmount(last.group(2)!);
      final tail = l.substring(last.end);
      final year = v >= 1990 && v <= 2100 && !last.group(2)!.contains(',');
      if (v >= 10 &&
          !year &&
          RegExp(
            r'^(?:\s*(?:flat|fixed|total|only))?[\s.,!]*$',
            caseSensitive: false,
          ).hasMatch(tail)) {
        final desc = _trimPunct(
          cut(l, last).replaceAll(
            RegExp(r'\b(flat|fixed|total|only)\b', caseSensitive: false),
            ' ',
          ),
        );
        items.add(
          ParsedItem(
            desc: desc.isEmpty ? 'Line item' : desc,
            qty: 1,
            rate: v,
            unit: 'x',
            confidence: 58,
            source: l,
            why: 'No currency or quantity, so the last number was read as a flat price. Confirm or adjust.',
          ),
        );
        continue;
      }
    }

    final h = headerRe.firstMatch(l);
    if (lineNo == 0 &&
        h != null &&
        candidate == null &&
        !RegExp(r'\d').hasMatch(h.group(1)!) &&
        h.group(1)!.trim().split(RegExp(r'\s+')).length <= 4) {
      candidate = _trimPunct(h.group(1)!);
      title ??= _cap(_trimPunct(h.group(2)!));
      continue;
    }
    unparsed.add(l);
  }

  return ParsedNotes(
    items,
    unparsed,
    clientId: clientId,
    clientCandidate: candidate,
    title: title,
    terms: terms,
    tax: tax,
    discountPct: discPct,
    discountFlat: discFlat,
  );
}

List<Widget> _spaced(List<Widget> w, double gap) => [
  for (final (i, x) in w.indexed) ...[if (i > 0) SizedBox(width: gap), x],
];

String _n(double v) {
  final r = double.parse(v.toStringAsFixed(2));
  return r % 1 == 0 ? r.toInt().toString() : r.toString();
}

int? _termDays(String terms) => terms == 'Due on receipt'
    ? 0
    : int.tryParse(terms.replaceAll(RegExp(r'\D'), ''));

// ---------------------------------------------------------------------------------------------------------------------

class _Edit {
  final double? qty, rate;
  final bool removed;
  const _Edit({this.qty, this.rate, this.removed = false});
}

typedef _ClientPick = ({String? id, String? name});
typedef _View = ({
  ParsedNotes p,
  List<ParsedItem> items,
  int removed,
  double subtotal,
  double discount,
  double tax,
  double total,
  String terms,
  Client? client,
  String? newName,
});

class MagicPage extends StatefulWidget {
  /// Tests pass a fake recognizer; the app uses the phone's.
  final VoiceController? voice;
  const MagicPage({super.key, this.voice});
  @override
  State<MagicPage> createState() => _MagicPageState();
}

class _MagicPageState extends State<MagicPage> {
  final ctl = TextEditingController();

  bool focusMode = false;
  bool aiBusy = false;
  bool creating = false;
  String? aiNote; // result of the last clean up
  bool aiNoteBad = false;
  String? undoText; // pad text from before the model rewrote it

  // voice typing: dictated lines are appended to the pad, one line per utterance
  late final VoiceController voice = widget.voice ?? VoiceController(engine: SherpaEngine(voicePack));
  String _voicePrefix = '';
  bool _utteranceOpen = false;

  // live mode: the model re-reads the notes after you pause, streaming its lines into the extraction pane
  Timer? _debounce;
  StreamSubscription<String>? _sub;
  bool liveBusy = false;
  String? liveText; // the model's lines for [liveFor]
  String? liveFor; // the trimmed pad text liveText was made from
  String? liveError;

  _ClientPick? clientChoice;
  double? taxOverride, discountOverride;
  String? termsOverride;
  final Map<String, _Edit> edits = {}; // keyed by the source line, so they survive edits elsewhere in the pad

  bool get busy => aiBusy || creating;

  @override
  void initState() {
    super.initState();
    voice.addListener(_onVoiceChange);
    Ai.warmUp(); // no-op if the model is already loaded
  }

  void _onVoiceChange() {
    if (mounted) setState(() {});
  }

  /// Dictated text goes after what is already in the pad, as its own line; partial results replace the line as it is spoken.
  void _onVoice(String text, bool isFinal) {
    if (!mounted) return;
    if (!_utteranceOpen) {
      final t = ctl.text.trimRight();
      _voicePrefix = t.isEmpty ? '' : '$t\n';
      _utteranceOpen = true;
    }
    final next = _voicePrefix + text + (isFinal ? '\n' : '');
    setState(
      () => ctl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      ),
    );
    if (isFinal) _utteranceOpen = false;
  }

  Future<void> _toggleVoice() async {
    if (voice.listening) {
      await voice.stop();
      _utteranceOpen = false;
      if (!mounted) return;
      setState(() => ctl.text = ctl.text.trimRight());
      _scheduleLive(); // read what was dictated once the mic is off
      return;
    }
    if (busy) return;
    if (widget.voice == null && !await _ensureVoicePack()) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _stopLive();
    voice.clearMessage();
    final s = context.read<Store>();
    await voice.start(
      _onVoice,
      phrases: [
        ...s.clients.map((c) => c.name).take(20),
        'tax',
        'net',
        'discount',
      ],
    );
  }

  /// First use: offers the one-time download of the offline speech model. True once it is on the phone.
  Future<bool> _ensureVoicePack() async {
    if (voicePack.ready) return true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => const _VoicePackSheet(),
    );
    return ok == true && voicePack.ready;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    Ai.cancel();
    voice
      ..removeListener(_onVoiceChange)
      ..stop();
    if (widget.voice == null) voice.dispose();
    ctl.dispose();
    super.dispose();
  }

  /// What the extraction pane reads: the model's lines while they match the current notes, otherwise the notes themselves (instant quick parse).
  String get _source {
    final t = liveText;
    return t != null && liveFor == ctl.text.trim() ? t : ctl.text;
  }

  void _stopLive({bool clear = false}) {
    _debounce?.cancel();
    _sub?.cancel();
    _sub = null;
    Ai.cancel();
    if (liveBusy || clear) {
      setState(() {
        liveBusy = false;
        if (clear) liveText = liveFor = null;
      });
    }
  }

  /// Called on every edit: drops the stale run and starts a new one once typing pauses.
  void _scheduleLive() {
    final on = context.read<Store>().profile.liveMode && Ai.ready;
    if (!on || voice.listening) return;
    _stopLive();
    final t = ctl.text.trim();
    if (t.length < 6 || !RegExp(r'\d').hasMatch(t)) {
      if (liveText != null) setState(() => liveText = liveFor = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 700), _runLive);
  }

  void _runLive() {
    final raw = ctl.text.trim();
    if (raw.isEmpty || !mounted) return;
    var last = '';
    setState(() {
      liveBusy = true;
      liveError = null;
    });
    _sub = Ai.padStream(raw).listen(
      (acc) {
        last = acc;
        if (!mounted) return;
        // while it streams only finished lines are shown, so a half-written number never appears
        final lines = cleanPad(completeLines(acc));
        setState(() {
          liveFor = raw;
          liveText = lines.isEmpty ? null : lines;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          liveBusy = false;
          liveError =
              'Live mode could not run the model, so the quick parser is used.';
        });
      },
      onDone: () {
        if (!mounted) return;
        final full = cleanPad(last);
        setState(() {
          liveBusy = false;
          liveFor = raw;
          liveText = full.isEmpty ? null : full;
        });
      },
      cancelOnError: true,
    );
  }

  void _toggleLive() {
    if (!Ai.ready) return _openSettings();
    final s = context.read<Store>();
    s.updateProfile((p) => p.liveMode = !p.liveMode);
    if (s.profile.liveMode) {
      _scheduleLive();
    } else {
      _stopLive(clear: true);
    }
  }

  void _openSettings() => Navigator.push(context, zoom(const SettingsPage()));

  /// Runs the on-device model over the raw notes. The pad is read-only while it runs, and the result is dropped if the page was closed.
  Future<void> _aiCleanUp() async {
    if (busy) return;
    final raw = ctl.text;
    if (raw.trim().isEmpty) {
      toast(context, 'Write some notes first');
      return;
    }
    FocusScope.of(context).unfocus();
    _stopLive(clear: true);
    setState(() {
      aiBusy = true;
      aiNote = null;
    });
    final out = await Ai.pad(raw);
    if (!mounted) return;
    final read = out == null
        ? null
        : parseNotes(
            out,
            context.read<Store>().clients,
            context.read<Store>().profile.currency,
          );
    setState(() {
      aiBusy = false;
      if (out == null || read == null || read.items.isEmpty) {
        aiNoteBad = true;
        aiNote = 'The model could not read these notes, so the quick parser is used. Check the model in Settings.';
        return;
      }
      aiNoteBad = false;
      aiNote = 'Cleaned up on-device${Ai.stats.value == null ? '.' : ' · ${Ai.stats.value!.summary}'}';
      undoText = raw;
      edits.clear();
      clientChoice = null;
      taxOverride = discountOverride = null;
      termsOverride = null;
      ctl.text = out;
    });
  }

  void _undoCleanUp() {
    final t = undoText;
    if (t == null) return;
    setState(() {
      ctl.text = t;
      undoText = null;
      aiNote = null;
    });
  }

  void _insert(String text) {
    final v = ctl.value;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    final next = v.text.replaceRange(sel.start, sel.end, text);
    setState(
      () => ctl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: sel.start + text.length),
      ),
    );
  }

  void _appendLine(String text) {
    final t = ctl.text.trimRight();
    setState(
      () => ctl.value = TextEditingValue(
        text: t.isEmpty ? text : '$t\n$text',
        selection: TextSelection.collapsed(
          offset: (t.isEmpty ? text : '$t\n$text').length,
        ),
      ),
    );
  }

  // ---- the numbers on screen, always recomputed from the pad + the user's overrides
  _View _view(Store s) {
    final p = parseNotes(_source, s.clients, s.profile.currency);
    final items = <ParsedItem>[];
    var removed = 0;
    for (final i in p.items) {
      final e = edits[i.source];
      if (e?.removed ?? false) {
        removed++;
        continue;
      }
      items.add(
        e == null
            ? i
            : ParsedItem(
                desc: i.desc,
                qty: e.qty ?? i.qty,
                rate: e.rate ?? i.rate,
                unit: i.unit,
                confidence: 100,
                source: i.source,
                why: 'Confirmed by you.',
              ),
      );
    }
    final subtotal = items.fold(0.0, (a, i) => a + i.amount);
    final discount =
        (discountOverride ??
                p.discountPct ??
                (p.discountFlat != null && subtotal > 0
                    ? p.discountFlat! / subtotal * 100
                    : 0))
            .clamp(0.0, 100.0);
    final tax = taxOverride ?? p.tax ?? s.profile.defaultTax;
    final taxable = subtotal * (1 - discount / 100);
    final client =
        s.client(clientChoice?.id) ??
        (clientChoice == null ? s.client(p.clientId) : null);
    final newName = client != null
        ? null
        : (clientChoice?.name ?? p.clientCandidate);
    return (
      p: p,
      items: items,
      removed: removed,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: taxable * (1 + tax / 100),
      terms: termsOverride ?? p.terms ?? 'Net ${s.profile.dueDays}',
      client: client,
      newName: newName == null || newName.trim().isEmpty
          ? null
          : newName.trim(),
    );
  }

  Future<_ClientPick?> _pickClient(String initial, {String? why}) =>
      showDialog<_ClientPick>(
        context: context,
        builder: (_) =>
            _ClientDialog(initial: initial, why: why, clients: store.clients),
      );

  /// A document or task board always belongs to a client: use the detected one, or ask. Creates the client only when it has to.
  Future<String?> _resolveClient() async {
    final s = context.read<Store>();
    var v = _view(s);
    if (v.client == null) {
      final name = v.newName ?? '';
      final pick = await _pickClient(
        name,
        why: name.isEmpty
            ? 'Who is this for? Pick a client or add a new one.'
            : '"$name" is not in your clients yet.',
      );
      if (pick == null || !mounted) return null;
      setState(() => clientChoice = pick);
      v = _view(s);
    }
    if (v.client != null) return v.client!.id;
    final byName = s.clients
        .where((c) => c.name.trim().toLowerCase() == v.newName!.toLowerCase())
        .firstOrNull;
    if (byName != null) return byName.id;
    final c = Client(name: v.newName!);
    s.putClient(c);
    return c.id;
  }

  Project? _projectFor(Store s, String clientId, String? title) {
    final mine = s.projects
        .where((p) => p.clientId == clientId && p.status == 'active')
        .toList();
    final t = (title ?? '').toLowerCase();
    final named = t.isEmpty
        ? null
        : mine
              .where(
                (p) =>
                    p.name.isNotEmpty &&
                    (t.contains(p.name.toLowerCase()) ||
                        p.name.toLowerCase().contains(t)),
              )
              .firstOrNull;
    return named ?? (mine.length == 1 ? mine.first : null);
  }

  Future<void> _create(String kind) async {
    if (busy) return;
    final s = context.read<Store>();
    final v = _view(s);
    if (v.items.isEmpty) {
      toast(
        context,
        'Nothing to build yet. Add a line with a price, like "logo 8h @ rate" or "banner 2k".',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => creating = true);
    try {
      final cid = await _resolveClient();
      if (cid == null || !mounted) return;
      final fresh = _view(s); // the pad cannot change while the dialog is open, but a client may have just been added
      final title = fresh.p.title;
      if (kind == 'board') {
        final name = title ?? '${s.clientName(cid)} project';
        final pr = Project(
          clientId: cid,
          name: name,
          budget: fresh.subtotal,
          todos: [
            for (final i in fresh.items)
              Todo(text: i.desc, hours: i.unit == 'h' ? '${_n(i.qty)}h' : ''),
          ],
        );
        s.putProject(pr);
        toast(
          context,
          'Task board created · ${pr.todos.length} ${pr.todos.length == 1 ? 'task' : 'tasks'}',
        );
        Navigator.pushReplacement(context, zoom(ProjectDetailPage(pr.id)));
        return;
      }
      final doc =
          s.newDoc(
              kind,
              clientId: cid,
              projectId: _projectFor(s, cid, title)?.id,
            )
            ..title = title ?? ''
            ..items = [
              for (final i in fresh.items)
                LineItem(desc: i.desc, qty: i.qty, rate: i.rate, unit: i.unit),
            ]
            ..taxPct = fresh.tax
            ..discount = fresh.discount
            ..terms = fresh.terms;
      final days = _termDays(fresh.terms);
      if (days != null) doc.due = doc.date.add(Duration(days: days));
      s.putDoc(doc);
      toast(context, '${doc.number} created');
      Navigator.pushReplacement(context, zoom(DocDetailPage(doc.id)));
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> _editItem(ParsedItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _ItemSheet(
        item: item,
        onChange: (q, r) =>
            setState(() => edits[item.source] = _Edit(qty: q, rate: r)),
        onRemove: () =>
            setState(() => edits[item.source] = const _Edit(removed: true)),
      ),
    );
  }

  Future<void> _editNumber(
    String title,
    double current,
    ValueChanged<double> apply,
  ) async {
    final v = await showDialog<double>(
      context: context,
      builder: (_) => _NumberDialog(title: title, initial: current),
    );
    if (v != null && mounted) setState(() => apply(v));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    context
        .watch<
          ModelDownloads
        >(); // a model finishing its download should light up Clean up
    final kb = MediaQuery.viewInsetsOf(context).bottom > 0;
    final v = _view(s);
    final model = s.profile.heuristicFallback ? null : Ai.current;
    final empty = ctl.text.trim().isEmpty;

    return PopScope(
      canPop: empty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final ok = await confirm(
          context,
          'Discard these notes?',
          'They are not saved anywhere yet.',
          verb: 'Discard',
        );
        if (ok) nav.pop();
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(model, empty),
              if (!kb) _statusLine(model),
              Expanded(key: const ValueKey('pad-pane'), flex: 3, child: _pad(s)), // keyed: the field must survive the keyboard changing the layout
              if (kb) _compactBar(v),
              if (!kb && !focusMode)
                Expanded(flex: 7, child: _extraction(s, v)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(AiModel? model, bool empty) {
    final canClean = model != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          _Tap(
            label: 'Close',
            onTap: () => Navigator.maybePop(context),
            child: const Text(
              'Close',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: C.muted,
              ),
            ),
          ),
          const Spacer(),
          _Tap(
            label: canClean
                ? 'Clean up notes with the on-device model'
                : 'Set up the on-device model',
            onTap: aiBusy ? null : (canClean ? _aiCleanUp : _openSettings),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: canClean ? C.orange : C.chipBg,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (aiBusy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: canClean ? Colors.white : C.muted,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    aiBusy ? 'Reading…' : (canClean ? 'Clean up' : 'Set up AI'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: canClean ? Colors.white : C.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          _Tap(
            label: focusMode ? 'Show extraction' : 'Focus on notes',
            onTap: () => setState(() => focusMode = !focusMode),
            child: Text(
              focusMode ? 'Preview' : 'Focus',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: C.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveChip() {
    final on = context.read<Store>().profile.liveMode;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: _Tap(
        label: on ? 'Turn live mode off' : 'Turn live mode on',
        onTap: _toggleLive,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? C.orange : C.chipBg,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: on ? Colors.white : C.dim,
                      shape: BoxShape.circle,
                    ),
                  )
                  .animate(
                    target: on && liveBusy ? 1 : 0,
                    onPlay: (c) => c.repeat(reverse: true),
                  )
                  .fade(begin: 1, end: .3, duration: 500.ms),
              const SizedBox(width: 6),
              Text(
                'LIVE',
                style: mono(
                  11,
                  color: on ? Colors.white : C.muted,
                  weight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLine(AiModel? model) {
    final String text;
    Color color = C.muted;
    VoidCallback? action;
    String? actionLabel;
    if (voice.listening) {
      text = 'LISTENING · OFFLINE\nPause 2 seconds, or say "new line", for the next item';
      color = C.orange;
    } else if (voice.message != null) {
      text = voice.message!;
      color = voice.messageIsError ? C.red : C.muted;
      action = voice.clearMessage;
      actionLabel = 'OK';
    } else if (aiBusy) {
      text = '${model?.name.toUpperCase() ?? 'MODEL'} · READING YOUR NOTES…';
    } else if (liveBusy) {
      text = '${model?.name.toUpperCase() ?? 'MODEL'} · LIVE · READING…';
    } else if (liveError != null) {
      text = liveError!;
      color = C.red;
    } else if (aiNote != null) {
      text = aiNote!;
      color = aiNoteBad ? C.red : C.greenText;
      action = aiNoteBad
          ? _openSettings
          : (undoText != null ? _undoCleanUp : null);
      actionLabel = aiNoteBad ? 'Settings' : 'Undo';
    } else if (model != null) {
      final st = Ai.stats.value;
      text =
          'ON-DEVICE · ${model.name.toUpperCase()} · ${context.read<Store>().profile.hardware}${st == null ? '' : '\n${st.summary}'}';
    } else if (context.read<Store>().profile.heuristicFallback) {
      text = 'QUICK PARSER · the AI model is turned off in Settings';
      action = _openSettings;
      actionLabel = 'Settings';
    } else {
      text = 'QUICK PARSER · no AI model installed yet';
      action = _openSettings;
      actionLabel = 'Set up';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: model == null ? C.dim : C.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: mono(11, color: color, letterSpacing: 0.4),
            ),
          ),
          if (model != null) _liveChip(),
          if (action != null)
            _Tap(
              label: actionLabel!,
              onTap: action,
              child: Text(
                actionLabel,
                style: const TextStyle(
                  color: C.orange,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Tap to dictate, tap again to stop; long-press to pick the language. Rings follow the microphone level while listening.
  Widget _micButton() {
    final on = voice.listening;
    final enabled = !busy;
    return Semantics(
      button: true,
      label: on ? 'Stop voice typing' : 'Start voice typing',
      child: GestureDetector(
        child: _Tap(
          label: on ? 'Stop voice typing' : 'Start voice typing',
          onTap: enabled ? _toggleVoice : null,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (on)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 52 + 12 * voice.level,
                    height: 52 + 12 * voice.level,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.orange.withValues(alpha: .18 + .2 * voice.level),
                    ),
                  ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !enabled ? C.chipBg : (on ? C.orange : C.dark),
                    boxShadow: [
                      BoxShadow(
                        color: (on ? C.orange : Colors.black).withValues(
                          alpha: .25,
                        ),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(
                    on ? Icons.stop_rounded : Icons.mic_rounded,
                    color: enabled ? Colors.white : C.dim,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pad(Store s) {
    final chips = <(String, VoidCallback)>[
      ('@', () => _insert(' @ ')),
      ('h @', () => _insert('h @ ')),
      ('x @', () => _insert('x @ ')),
      if (s.profile.defaultTax > 0)
        (
          'Tax ${_n(s.profile.defaultTax)}%',
          () => _appendLine('tax ${_n(s.profile.defaultTax)}%'),
        ),
      (
        'Net ${s.profile.dueDays}',
        () => _appendLine('net ${s.profile.dueDays}'),
      ),
      ('% off', () => _insert('% off')),
    ];
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  key: const Key('magic-pad'),
                  controller: ctl,
                  readOnly: aiBusy || voice.listening,
                  onChanged: (_) {
                    setState(() {});
                    _scheduleLive();
                  },
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  style: mono(16, color: C.text, letterSpacing: 0),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.only(right: 64),
                    hintText: 'Jot it down, one thing per line.\n\nClient name - project name\nitem name 8h @ rate\nitem name 3x @ rate\nitem name flat price\ntax %, net days, % off',
                    hintMaxLines: 10,
                    hintStyle: TextStyle(
                      color: C.dim,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              Positioned(right: 16, bottom: 4, child: _micButton()),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final (label, tap) in chips)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Tap(
                    label: 'Insert $label',
                    onTap: aiBusy ? null : tap,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: C.chipBg,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        label,
                        style: mono(12, color: C.text, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Shown instead of the extraction pane while the keyboard is up, so the pad keeps its room.
  Widget _compactBar(_View v) {
    return Container(
      color: C.dark,
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${v.items.length} ${v.items.length == 1 ? 'LINE' : 'LINES'} · ${money(v.total)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(12, color: C.textLight, weight: FontWeight.w700),
            ),
          ),
          _Tap(
            label: 'Hide keyboard',
            onTap: () => FocusScope.of(context).unfocus(),
            child: const Text(
              'Done',
              style: TextStyle(
                color: C.amberLight,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _extraction(Store s, _View v) {
    final empty = ctl.text.trim().isEmpty;
    final clientText =
        v.client?.name ?? (v.newName != null ? 'New · ${v.newName}' : 'Choose');
    const termOptions = ['Due on receipt', 'Net 7', 'Net 14', 'Net 30'];
    return Container(
      decoration: const BoxDecoration(
        color: C.dark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${liveText != null && liveFor == ctl.text.trim() ? 'AI · LIVE' : 'LIVE'} EXTRACTION · ${v.items.length} ${v.items.length == 1 ? 'LINE' : 'LINES'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: mono(10, color: C.dimLight, letterSpacing: 1.2),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    money(v.total),
                    style: display(20, color: C.textLight),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _spaced([
                      _MetaPill(
                        label: 'CLIENT',
                        value: clientText,
                        valueColor: v.client != null
                            ? C.textLight
                            : C.amberLight,
                        onTap: () async {
                          final pick = await _pickClient(
                            v.client?.name ?? v.newName ?? '',
                          );
                          if (pick != null && mounted) {
                            setState(() => clientChoice = pick);
                          }
                        },
                      ),
                      _MetaPill(
                        label: 'TAX',
                        value: '${_n(v.tax)}%',
                        onTap: () =>
                            _editNumber('Tax %', v.tax, (x) => taxOverride = x),
                      ),
                      _MetaPill(
                        label: 'TERMS',
                        value: v.terms,
                        onTap: () {
                          final opts = termOptions.contains(v.terms)
                              ? termOptions
                              : [v.terms, ...termOptions];
                          setState(
                            () => termsOverride =
                                opts[(opts.indexOf(v.terms) + 1) % opts.length],
                          );
                        },
                      ),
                      _MetaPill(
                        label: 'DISCOUNT',
                        value: '${_n(v.discount)}%',
                        onTap: () => _editNumber(
                          'Discount %',
                          v.discount,
                          (x) => discountOverride = x,
                        ),
                      ),
                    ], 6),
                  ),
                ),
                const SizedBox(height: 8),
                if (v.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      empty
                          ? 'Your notes are read here as you type. Add a line with a price to get started.'
                          : 'No priced lines yet. Add an amount to a line, like "banner 2k" or "logo 8h @ rate".',
                      style: const TextStyle(
                        color: C.dimLight,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                for (final i in v.items)
                  Pressable(
                    onTap: () => _editItem(i),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      constraints: const BoxConstraints(minHeight: 44),
                      decoration: BoxDecoration(
                        color: C.cardDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: i.confidence < 80
                              ? C.amber
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  i.desc,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: C.textLight,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  '${_n(i.qty)}${i.unit == 'x' || i.unit == '×' ? '' : ' ${i.unit}'} × ${money(i.rate)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: mono(11, color: C.dimLight),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    money(i.amount),
                                    style: mono(13, color: C.textLight),
                                  ),
                                ),
                                Text(
                                  '${i.confidence}% sure',
                                  style: mono(
                                    10,
                                    color: i.confidence >= 90
                                        ? C.greenLight
                                        : C.amberLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (v.removed > 0)
                  _Tap(
                    label: 'Restore removed lines',
                    onTap: () =>
                        setState(() => edits.removeWhere((_, e) => e.removed)),
                    child: Text(
                      '${v.removed} removed · Restore',
                      style: const TextStyle(
                        color: C.amberLight,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                if (v.p.unparsed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Kept as notes (no price): ${v.p.unparsed.join(" · ")}',
                      style: mono(11, color: C.dimLight),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  'Quotation',
                  C.orange,
                  Colors.white,
                  busy ? null : () => _create('quote'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _ActionButton(
                  'Invoice',
                  C.bg,
                  C.dark,
                  busy ? null : () => _create('invoice'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _ActionButton(
                  'Task board',
                  C.cardDarkElevated,
                  C.textLight,
                  busy ? null : () => _create('board'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tap target that is at least 44x44 with a screen-reader label.
class _Tap extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  const _Tap({required this.label, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Pressable(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Center(
          widthFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final String text;
  final Color bg, fg;
  final VoidCallback? onTap;
  const _ActionButton(this.text, this.bg, this.fg, this.onTap);

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? .5 : 1,
    child: Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    ),
  );
}

class _MetaPill extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  final VoidCallback onTap;
  const _MetaPill({
    required this.label,
    required this.value,
    this.valueColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label $value. Tap to change',
    excludeSemantics: true,
    child: Pressable(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 64,
          maxWidth: 190,
          minHeight: 44,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: C.cardDarkElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: mono(9, color: C.dimLight)),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? C.textLight,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Edit one extracted line. Quantity and rate are typed, not nudged; invalid values are explained and not applied.
class _ItemSheet extends StatefulWidget {
  final ParsedItem item;
  final void Function(double qty, double rate) onChange;
  final VoidCallback onRemove;
  const _ItemSheet({
    required this.item,
    required this.onChange,
    required this.onRemove,
  });
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final qty = TextEditingController(text: _n(widget.item.qty));
  late final rate = TextEditingController(text: _n(widget.item.rate));
  String? qtyErr, rateErr;

  @override
  void dispose() {
    qty.dispose();
    rate.dispose();
    super.dispose();
  }

  void _apply() {
    final q = double.tryParse(qty.text.replaceAll(',', '').trim());
    final r = double.tryParse(rate.text.replaceAll(',', '').trim());
    setState(() {
      qtyErr = q == null || q <= 0 ? 'Enter a number above 0' : null;
      rateErr = r == null || r < 0 ? 'Enter a number, 0 or more' : null;
    });
    if (qtyErr == null && rateErr == null) widget.onChange(q!, r!);
  }

  InputDecoration _dec(String label, String? err) => InputDecoration(
    labelText: label,
    errorText: err,
    filled: true,
    fillColor: C.bg,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CONFIDENCE INSPECTOR',
              style: mono(10, color: C.dim, letterSpacing: 1.0),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: C.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SOURCE LINE', style: mono(9, color: C.dim)),
                  const SizedBox(height: 2),
                  Text(it.source, style: mono(13, color: C.text)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${it.confidence}% sure. ${it.why}',
              style: const TextStyle(
                fontSize: 12.5,
                color: C.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: qty,
                    onChanged: (_) => _apply(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: _dec('Quantity (${it.unit})', qtyErr),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: rate,
                    onChanged: (_) => _apply(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    decoration: _dec('Rate', rateErr),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Tap(
                  label: 'Remove this line',
                  onTap: () {
                    widget.onRemove();
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Remove this line',
                    style: TextStyle(
                      color: C.red,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Spacer(),
                _Tap(
                  label: 'Done',
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: C.orange,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Choose an existing client or type a new one.
class _ClientDialog extends StatefulWidget {
  final String initial;
  final String? why;
  final List<Client> clients;
  const _ClientDialog({required this.initial, required this.clients, this.why});
  @override
  State<_ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends State<_ClientDialog> {
  late final name = TextEditingController(text: widget.initial);
  String? err;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _submit() {
    final n = name.text.trim();
    if (n.isEmpty) {
      setState(() => err = 'Type the client name');
      return;
    }
    Navigator.pop<_ClientPick>(context, (id: null, name: n));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: C.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: C.border),
    ),
    title: Text('Client', style: display(20)),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.why != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                widget.why!,
                style: const TextStyle(
                  color: C.muted,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ),
          if (widget.clients.isNotEmpty) ...[
            Text('EXISTING', style: mono(10, color: C.dim)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in widget.clients)
                  ActionChip(
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onPressed: () => Navigator.pop<_ClientPick>(context, (
                      id: c.id,
                      name: null,
                    )),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Text('NEW CLIENT', style: mono(10, color: C.dim)),
          const SizedBox(height: 6),
          TextField(
            controller: name,
            autofocus: widget.clients.isEmpty,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (_) => err == null ? null : setState(() => err = null),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Client name',
              errorText: err,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel', style: TextStyle(color: C.muted)),
      ),
      TextButton(
        onPressed: _submit,
        child: const Text(
          'Use new client',
          style: TextStyle(color: C.orange, fontWeight: FontWeight.bold),
        ),
      ),
    ],
  );
}

class _NumberDialog extends StatefulWidget {
  final String title;
  final double initial;
  const _NumberDialog({required this.title, required this.initial});
  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final c = TextEditingController(text: _n(widget.initial));
  String? err;

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(c.text.trim());
    if (v == null || v < 0 || v > 100) {
      setState(() => err = 'Enter a percentage from 0 to 100');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: C.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: C.border),
    ),
    title: Text(widget.title, style: display(20)),
    content: TextField(
      controller: c,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(suffixText: '%', errorText: err),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel', style: TextStyle(color: C.muted)),
      ),
      TextButton(
        onPressed: _submit,
        child: const Text(
          'Apply',
          style: TextStyle(color: C.orange, fontWeight: FontWeight.bold),
        ),
      ),
    ],
  );
}


/// Bottom sheet that downloads the offline speech model the first time the mic is used.
class _VoicePackSheet extends StatelessWidget {
  const _VoicePackSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListenableBuilder(
          listenable: voicePack,
          builder: (context, _) {
            if (voicePack.ready) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) Navigator.pop(context, true);
              });
            }
            final busy = voicePack.busy;
            return Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Offline voice typing', style: display(22)),
                  const SizedBox(height: 8),
                  Text(
                    'Speech is recognised on your phone, so nothing you say is sent anywhere and it works without internet. '
                    'It needs a one-time ${VoicePack.sizeLabel()} download (English).',
                    style: const TextStyle(color: C.muted, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  if (busy) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: LinearProgressIndicator(value: voicePack.progress, minHeight: 8, color: C.orange, backgroundColor: C.draftBg),
                    ),
                    const SizedBox(height: 8),
                    Text('Downloading ${(voicePack.progress * 100).round()}%', style: mono(12, color: C.muted)),
                  ] else if (voicePack.state == VoiceState2.failed) ...[
                    Text(voicePack.error ?? 'Download failed.', style: const TextStyle(color: C.red, fontSize: 13)),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: _Tap(
                        label: busy ? 'Cancel download' : 'Not now',
                        onTap: () async {
                          if (busy) await voicePack.cancel();
                          if (context.mounted) Navigator.pop(context, false);
                        },
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(color: C.chipBg, borderRadius: BorderRadius.circular(14)),
                          child: Text(busy ? 'Cancel' : 'Not now', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    if (!busy) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _Tap(
                          label: 'Download voice model',
                          onTap: voicePack.download,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(14)),
                            child: Text(voicePack.state == VoiceState2.failed ? 'Retry' : 'Download ${VoicePack.sizeLabel()}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            );
          },
        ),
      );
}
