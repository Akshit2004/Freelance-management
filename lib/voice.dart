import 'dart:async';

import 'package:flutter/foundation.dart';

import 'numwords.dart';

/// Turns what the recognizer heard into the pad's own syntax, so the extractor reads spoken notes as well as typed ones:
///  - ALL CAPS recognizer output becomes normal text, each line starts with a capital
///  - spoken numbers become digits: "two thousand five hundred" -> 2500
///  - "new line" / "next item" start another line
///  - "3 reels at 2000" -> `reels 3x @ 2000`, "banner 3 at 1500" -> `banner 3x @ 1500`, "design 8 hours at 85" -> `design 8h @ 85`
///  - "2000 rupees" / "500 dollars" -> `₹2000` / `$500`, "logo design for 8000" -> `logo design 8000`
///  - "18 percent GST" -> `tax 18%`, "due in 7 days" stays as is (the extractor reads it)
String normalizeSpoken(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return '';
  if (!RegExp(r'[a-z]').hasMatch(t)) t = t.toLowerCase(); // streaming recognizers answer in capitals
  t = wordsToDigits(t);
  t = t.replaceAll(RegExp(r'\s*\b(?:new ?line|next line|next item)\b[.,]?\s*', caseSensitive: false), '\n');
  const price = r'(?=[₹$€£]?\s*\d)';
  final lines = t.split('\n').map((l) {
    var s = l.trim();
    s = s.replaceAllMapped(RegExp(r'(\d)\s*(?:percent|per cent)\b', caseSensitive: false), (m) => '${m[1]}%');
    s = s.replaceAllMapped(RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*(rupees?|rs\.?|inr)\b', caseSensitive: false), (m) => '₹${m[1]}');
    s = s.replaceAllMapped(RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*dollars?\b', caseSensitive: false), (m) => '\$${m[1]}');
    s = s.replaceAllMapped(RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*euros?\b', caseSensitive: false), (m) => '€${m[1]}');
    s = s.replaceAllMapped(RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*pounds?\b', caseSensitive: false), (m) => '£${m[1]}');
    s = s.replaceAllMapped(RegExp(r'\b(?:rupees?|rs\.?)\s*(\d)', caseSensitive: false), (m) => '₹${m[1]}');
    // "18% GST" / "18 percent VAT" -> "tax 18%"
    s = s.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s*%\s*(?:gst|vat|tax)\b', caseSensitive: false), (m) => 'tax ${m[1]}%');
    // hours: "design 8 hours at 85" / "8 hours of design at 85"
    s = s.replaceAllMapped(RegExp(r'^(\d+(?:\.\d+)?)\s*(?:hours?|hrs?)\s+(?:of\s+)?([A-Za-z][A-Za-z &\x27-]*?)\s+(?:at|@)\s+' + price, caseSensitive: false),
        (m) => '${m[2]} ${m[1]}h @ ');
    s = s.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s*(?:hours?|hrs?)\s+(?:at|@)\s+' + price, caseSensitive: false), (m) => '${m[1]}h @ ');
    // quantity first: "3 reels at 2000" -> "reels 3x @ 2000"
    s = s.replaceAllMapped(RegExp(r'^(\d+(?:\.\d+)?)\s*(?:x\s+)?([A-Za-z][A-Za-z &\x27-]*?)\s+(?:each\s+)?(?:at|@)\s+' + price, caseSensitive: false),
        (m) => '${m[2]} ${m[1]}x @ ');
    // quantity after the name: "banner 3 at 1500"
    s = s.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s+(?:each\s+)?(?:at|@)\s+' + price, caseSensitive: false), (m) => '${m[1]}x @ ');
    // "logo design for 8000" / "logo costs 8000" -> "logo design 8000"
    s = s.replaceAll(RegExp(r'\s+(?:for|costs?|is|are|charged)\s+' + price, caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  });
  return lines.where((l) => l.isNotEmpty).join('\n');
}

/// The speech recognizer behind a seam, so the controller can be tested without a microphone.
abstract class SpeechEngine {
  /// Prepares recognition (model + microphone permission). False if either is missing.
  Future<bool> init({required void Function(String status) onStatus, required void Function(String code, bool permanent) onError});
  Future<bool> hasPermission();

  /// Starts listening. Results arrive through [onResult]: the text of the current utterance so far (isFinal false),
  /// and once more when that utterance is finished (true).
  Future<void> listen({
    required List<String> phrases,
    required void Function(String words, bool isFinal) onResult,
    required void Function(double level) onLevel,
  });
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

enum VoiceState { idle, starting, listening }

/// Hands-free dictation. Keeps listening until [stop]; an engine that ends its session after a pause (status "done") is restarted.
class VoiceController extends ChangeNotifier {
  VoiceController({required this.engine, this.restartDelay = const Duration(milliseconds: 250)});

  final SpeechEngine engine;
  final Duration restartDelay;

  VoiceState state = VoiceState.idle;
  double level = 0; // 0..1 microphone level, for the animation
  String? message; // something the user should read
  bool messageIsError = false;

  bool _want = false, _ready = false;
  int _failures = 0;
  Timer? _restart;
  List<String> _phrases = const [];
  void Function(String text, bool isFinal)? _sink;

  bool get listening => state != VoiceState.idle;

  /// [sink] gets the normalised text so far for the current utterance (isFinal false) and once more when it's finished (true).
  Future<void> start(void Function(String text, bool isFinal) sink, {List<String> phrases = const []}) async {
    if (_want) return;
    _want = true;
    _sink = sink;
    _phrases = phrases;
    _failures = 0;
    message = null;
    _set(VoiceState.starting);
    if (!_ready) {
      _ready = await engine.init(onStatus: _onStatus, onError: _onError);
      if (!_ready) {
        _want = false;
        _fail(await engine.hasPermission()
            ? 'Voice typing could not start. Check that the voice model is downloaded (Settings).'
            : 'Voice typing needs the microphone. Allow it in Settings › Apps › Hustler › Permissions.');
        return;
      }
    }
    await _listen();
  }

  Future<void> stop() async {
    _want = false;
    _restart?.cancel();
    level = 0;
    _set(VoiceState.idle);
    try {
      await engine.stop();
    } catch (_) {}
  }

  Future<void> _listen() async {
    if (!_want) return;
    try {
      await engine.listen(
        phrases: _phrases,
        onResult: (words, fin) {
          final t = normalizeSpoken(words);
          if (t.isEmpty) return;
          _failures = 0;
          _sink?.call(t, fin);
        },
        onLevel: (l) {
          level = l;
          notifyListeners();
        },
      );
      _set(VoiceState.listening);
    } catch (e) {
      _retryOrFail('Voice typing could not start ($e).');
    }
  }

  void _onStatus(String s) {
    if ((s == 'done' || s == 'notListening') && _want && state != VoiceState.starting) _scheduleRestart();
  }

  void _onError(String code, bool permanent) {
    if (!_want) return;
    switch (code) {
      case 'error_no_match' || 'error_speech_timeout':
        return; // silence is not a failure
      case 'error_permission':
        _want = false;
        _fail('Voice typing needs the microphone. Allow it in Settings › Apps › Hustler › Permissions.');
      case 'error_busy':
        _scheduleRestart(const Duration(milliseconds: 700));
      default:
        _retryOrFail('Voice typing stopped ($code).');
    }
  }

  void _retryOrFail(String text) {
    if (++_failures >= 3) {
      _want = false;
      _fail(text);
    } else {
      _scheduleRestart(const Duration(milliseconds: 500));
    }
  }

  void _scheduleRestart([Duration? after]) {
    _restart?.cancel();
    _restart = Timer(after ?? restartDelay, _listen);
  }

  void _fail(String text) {
    message = text;
    messageIsError = true;
    level = 0;
    _set(VoiceState.idle);
  }

  void _set(VoiceState s) {
    state = s;
    notifyListeners();
  }

  void clearMessage() {
    if (message == null) return;
    message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _want = false;
    _restart?.cancel();
    engine.dispose().catchError((_) {});
    super.dispose();
  }
}
