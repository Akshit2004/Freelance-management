import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'downloads.dart';
import 'log.dart';
import 'models.dart';

/// Timings of the last model run. Shown in Magic so latency is measured instead of guessed.
class AiStats {
  final Duration load, firstToken, total;
  final int tokens;
  const AiStats({required this.load, required this.firstToken, required this.total, required this.tokens});

  double get tokensPerSecond {
    final decode = (total - firstToken).inMilliseconds;
    return decode <= 0 || tokens < 2 ? 0 : (tokens - 1) * 1000 / decode;
  }

  String get summary {
    final first = (firstToken.inMilliseconds / 1000).toStringAsFixed(1);
    final tps = tokensPerSecond;
    return [
      '${first}s to first word',
      if (tps > 0) '${tps.toStringAsFixed(0)} tok/s',
      if (load.inMilliseconds > 1500) 'model loaded in ${(load.inMilliseconds / 1000).toStringAsFixed(1)}s',
    ].join(' · ');
  }
}

/// Model text -> pad lines: drops Qwen3's `<think>` block (even an unfinished one), code fences, bullets and "Notes:" echoes.
String cleanPad(String raw) {
  final t = raw.replaceAll(RegExp(r'<think>[\s\S]*?(?:</think>|$)'), '').replaceAll(RegExp(r'```\w*'), '');
  return [
    for (final l in t.split('\n').map((l) => l.trim().replaceFirst(RegExp(r'^[-*•]\s+'), '')))
      if (l.isNotEmpty && !RegExp(r'^(notes?|output|lines?|json)\s*:', caseSensitive: false).hasMatch(l)) l
  ].join('\n');
}

/// While tokens are still arriving only finished lines are safe to read (a half-written "Banners 3x @ 15" would parse as 15).
String completeLines(String acc) {
  final i = acc.lastIndexOf('\n');
  return i < 0 ? '' : acc.substring(0, i);
}

/// On-device model access, built for low latency:
///  - the model is loaded once and kept (warmUp at launch / when Magic opens; freed after 10 idle minutes), so a request never pays the load;
///  - the prompt is short and the model answers in the pad's own compact line format, not JSON, so there is far less to generate;
///  - tokens stream out, so lines appear as they are written, and a newer request cancels an older one.
class Ai {
  static const _idleUnload = Duration(minutes: 10);
  static const _maxEstimateTokens = 450; // modules + subtasks for a big project
  static const _maxAnswerTokens = 160; // a long invoice is ~12 lines; anything past this is the model rambling
  static InferenceModel? _model;
  static String? _loaded; // id of the model currently held in memory
  static String? _loadedHw; // the Settings hardware ('GPU' / 'CPU') it was loaded for; changing it reloads the model
  static InferenceModelSession? _session;
  static Future<void>? _loading;
  static Future<void> _tail = Future.value(); // the engine runs one session at a time
  static int _gen = 0; // bumped by every request; an older request notices and stops
  static Timer? _idle;

  /// Timing of the last completed run.
  static final stats = ValueNotifier<AiStats?>(null);

  /// The selected model, only if its file is fully on disk. Nothing chosen yet: whatever finished downloading.
  static AiModel? get current {
    final chosen = aiModels.where((m) => m.id == store.profile.aiModel && downloads.isReady(m)).firstOrNull;
    return chosen ?? aiModels.where(downloads.isReady).firstOrNull;
  }

  /// A model is installed and the user hasn't switched to the quick parser.
  static bool get ready => current != null && !store.profile.heuristicFallback;

  static void _touch() {
    _idle?.cancel();
    _idle = Timer(_idleUnload, _unload);
  }

  static Future<void> _unload() async {
    _idle?.cancel();
    final m = _model;
    _model = null;
    _loaded = null;
    try {
      await m?.close();
    } catch (_) {}
  }

  /// Registers the on-disk file with the inference engine (instant, no copy, works offline) and makes it the active model.
  static Future<void> _register(AiModel m) =>
      FlutterGemma.installModel(modelType: m.type, fileType: ModelFileType.litertlm).fromFile(downloads.pathFor(m)).install();

  static Future<void> _ensureLoaded(AiModel m) {
    if (_loaded == m.id && _loadedHw == store.profile.hardware && _model != null) return Future.value();
    return _loading ??= _load(m).whenComplete(() => _loading = null);
  }

  /// Loads the weights and runs a one-word generation so GPU kernels are compiled before the first real request.
  static Future<void> _load(AiModel m) async {
    await _unload();
    await _register(m);
    final backends = store.profile.hardware == 'CPU' ? [PreferredBackend.cpu] : [PreferredBackend.gpu, PreferredBackend.cpu];
    for (final backend in backends) {
      InferenceModel? model;
      try {
        model = await FlutterGemma.getActiveModel(maxTokens: 1024, preferredBackend: backend);
        final s = await model.createSession(temperature: 0.1, topK: 1);
        try {
          await s.addQueryChunk(Message.text(text: 'Say ok.', isUser: true));
          await s.getResponseAsync().first;
          await s.stopGeneration();
        } catch (_) {
          // the warm-up word is best effort; a model that created a session is usable
        } finally {
          await s.close();
        }
        _model = model;
        _loaded = m.id;
        _loadedHw = store.profile.hardware;
        Log.ai('loaded ${m.id} on ${backend.name}');
        return;
      } catch (_) {
        try {
          await model?.close();
        } catch (_) {}
        if (backend == backends.last) rethrow; // GPU failed: fall back to CPU; CPU failed: give up
      }
    }
  }

  /// Loads the selected model in the background so the first request is fast. Safe to call any time.
  static Future<void> warmUp() async {
    final m = current;
    if (m == null || store.profile.heuristicFallback) return;
    try {
      await _ensureLoaded(m);
      _touch();
    } catch (_) {}
  }

  static Future<void> use(AiModel m) async {
    await _unload();
    await _register(m);
    store.profile.aiModel = m.id;
    store.save();
    unawaited(warmUp());
  }

  static Future<void> remove(AiModel m) async {
    if (_loaded == m.id) await _unload();
    await downloads.remove(m);
    if (store.profile.aiModel == m.id) {
      store.profile.aiModel = '';
      store.save();
    }
  }

  /// Stops whatever is generating (the page was closed, or the notes changed).
  static void cancel() {
    _gen++;
    final s = _session;
    if (s != null) unawaited(s.stopGeneration().catchError((_) {}));
  }

  /// Streams the model's answer for [raw] notes as cumulative text (each event is everything written so far).
  /// Use [cleanPad] / [completeLines] on it. A newer call cancels this one. Throws if no model is usable.
  static Stream<String> padStream(String raw) => _stream(
        (m) => _prompt(raw, store.clients.map((c) => c.name).toList(), m),
        (soFar, tokens) => RegExp(r'\n\s*\n').hasMatch(soFar) || soFar.contains('Notes:') || tokens >= _maxAnswerTokens, // the answer is complete
      );

  static Stream<String> _stream(String Function(AiModel) buildPrompt, bool Function(String soFar, int tokens) isDone) async* {
    final m = current;
    if (m == null || store.profile.heuristicFallback) throw StateError('No on-device model is ready');
    final mine = ++_gen;
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    final prevSession = _session;
    if (prevSession != null) unawaited(prevSession.stopGeneration().catchError((_) {}));
    try {
      await prev;
      if (mine != _gen) return;
      final t0 = DateTime.now();
      await _ensureLoaded(m);
      final load = DateTime.now().difference(t0);
      if (mine != _gen) return;
      final s = await _model!.createSession(temperature: 0.1, topK: 1);
      _session = s;
      try {
        final prompt = buildPrompt(m);
        final tPrefill = DateTime.now();
        await s.addQueryChunk(Message.text(text: prompt, isUser: true));
        final t1 = DateTime.now();
        final promptTokens = await s.sizeInTokens(prompt).catchError((_) => -1);
        debugPrint('[Ai] ${m.id} load=${load.inMilliseconds}ms addChunk=${t1.difference(tPrefill).inMilliseconds}ms promptTokens=$promptTokens');
        Duration? first;
        var tokens = 0;
        final buf = StringBuffer();
        await for (final tok in s.getResponseAsync()) {
          if (mine != _gen) break;
          first ??= DateTime.now().difference(t1);
          tokens++;
          buf.write(tok);
          yield buf.toString();
          final soFar = buf.toString().trim();
          if (soFar.isNotEmpty && isDone(soFar, tokens)) break;
        }
        if (mine == _gen && first != null) {
          stats.value = AiStats(load: load, firstToken: first, total: DateTime.now().difference(t1), tokens: tokens);
          debugPrint('[Ai] firstToken=${first.inMilliseconds}ms tokens=$tokens total=${DateTime.now().difference(t1).inMilliseconds}ms ${stats.value!.tokensPerSecond.toStringAsFixed(1)} tok/s');
        }
      } finally {
        if (identical(_session, s)) _session = null;
        try {
          await s.stopGeneration();
        } catch (_) {}
        await s.close();
      }
    } finally {
      done.complete();
      _touch();
    }
  }

  /// The model's whole answer as pad lines, or null if it failed or wrote nothing usable.
  static Future<String?> pad(String raw) async {
    var last = '';
    try {
      await for (final acc in padStream(raw)) {
        last = acc;
      }
    } catch (_) {
      return null;
    }
    final out = cleanPad(last);
    return out.isEmpty ? null : out;
  }

  // Short on purpose: every prompt token costs prefill time on a phone.
  static String _prompt(String raw, List<String> known, AiModel m) => '''
You convert a freelancer's rough notes into invoice lines. Write only the lines, nothing else.
Line 1: the client's name, then " - " and the project name only if the notes name one. Skip line 1 if no client is named.${known.isEmpty ? '' : ' Known clients: ${known.take(12).join(', ')}.'}
Then one line per billable item: its name, quantity and "x", then "@" and the price of ONE unit as a plain number. 5k = 5000, 1.5L = 150000. Hours look like "8h @ 85".
Last line, only if mentioned: tax %, net days, % off, for example "tax 5%, net 30, 10% off".

Example. Notes: invoice dev studio for 2 posters at 1.5k each and a 40 minute call 3k, due in 10 days
dev studio
Poster 2x @ 1500
Call 1x @ 3000
net 10

Now do the same for these notes. Write only the answer lines.
Notes: $raw${m.id == 'qwen3' ? ' /no_think' : ''}
''';

  /// Why the last [estimate] returned null, for the user.
  static String estimateNote = '';

  /// One model call; returns everything it wrote (stopped early by [isDone]), or null if it errored.
  static Future<String?> _ask(String Function(AiModel) prompt, bool Function(String soFar, int tokens) isDone) async {
    var last = '';
    try {
      await for (final acc in _stream(prompt, isDone)) {
        last = acc;
      }
    } catch (e) {
      Log.ai('model call failed: $e');
      return null;
    }
    return last;
  }

  /// Rough scope for a project from its title and description, or null if the model failed or wrote nothing usable.
  /// Two steps, because a small model can't hold "area > features" in one answer: first the main deliverables, then one short
  /// call per deliverable for the features inside it (its subtasks). [onProgress] gets (finished, total) as the second step runs.
  /// With an [hourlyRate] the budget is hours x rate; without one it is the model's own guess (small models price badly).
  static Future<ProjectEstimate?> estimate(String title, String desc, String currency, double hourlyRate, {void Function(int done, int total)? onProgress}) async {
    final first = await _ask(
      (m) => _estimatePrompt(title, desc, currency, m),
      (soFar, tokens) => tokens >= _maxEstimateTokens || RegExp(r'\n\s*(Project|Example)\b').hasMatch(soFar), // a new "Project:" = it started another example
    );
    if (first == null) {
      estimateNote = 'The model stopped with an error.';
      return null;
    }
    Log.ai('estimate raw: ${first.replaceAll('\n', ' / ')}');
    final base = ProjectEstimate.parse(first, rate: hourlyRate);
    if (base == null) {
      estimateNote = first.trim().isEmpty ? 'The model wrote nothing.' : 'It did not follow the format.';
      return null;
    }
    estimateNote = '';
    final parts = base.todos.take(8).toList();
    onProgress?.call(0, parts.length);
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i], target = part.hoursValue;
      final raw = await _ask(
        (m) => _featuresPrompt(title, desc, part.text, target, m),
        (soFar, tokens) => tokens >= 140 || RegExp(r'\n\s*(Project|Example)\b').hasMatch(soFar),
      );
      Log.ai('features for "${part.text}": ${raw?.replaceAll('\n', ' / ')}');
      final feats = ProjectEstimate.parse('budget 1\n${raw ?? ''}')?.todos.where((t) => t.sub.isEmpty).toList() ?? const <Todo>[];
      if (feats.length >= 2) {
        // the model's feature hours only set the proportions; the deliverable keeps the hours it was given in step one
        final sum = feats.fold(0.0, (a, t) => a + t.hoursValue);
        for (final f in feats) {
          f.hours = Todo.fmtHours(target > 0 && sum > 0 ? max(0.5, (f.hoursValue * target / sum * 2).round() / 2) : f.hoursValue);
        }
        part.sub.addAll(feats.take(6));
        part.hours = ''; // a deliverable with subtasks counts its subtasks' hours
      }
      onProgress?.call(i + 1, parts.length);
    }
    final todos = [...parts, ...base.todos.skip(8)];
    final hours = ProjectEstimate(0, todos).hours;
    return hourlyRate > 0 ? ProjectEstimate((hours * hourlyRate).roundToDouble(), todos, fromRate: true) : ProjectEstimate(base.budget, todos);
  }

  // The example is real software scale on purpose: a small model copies the example's size, so a tiny example gave tiny estimates.
  static String _estimatePrompt(String title, String desc, String currency, AiModel m) => '''
You estimate freelance projects. Write only the answer lines.
Line 1: "budget" and a fair total price in $currency as a plain number.
Then 5 to 8 main parts of the project, one per line: name | hours
Be realistic: a website takes 40 to 120 hours, a full app or CRM takes 150 to 400 hours.

Example. Project: Salon booking app. Mobile app to book appointments, with login, online payments and an admin panel.
budget 240000
Login and accounts | 24
Appointment booking | 40
Payments | 28
Admin panel | 36
Notifications | 16
Testing and launch | 30

Now do the same. Write only the answer lines.
Project: $title. $desc${m.id == 'qwen3' ? ' /no_think' : ''}
''';

  static String _featuresPrompt(String title, String desc, String part, double hours, AiModel m) => '''
You list the features inside one part of a software project. Write only the answer lines.
Write 3 to 5 features, one per line: feature | hours
The hours add up to about ${hours > 0 ? Todo.fmtHours(hours).replaceAll('h', '') : '20'}.

Example. Project: Salon booking app. Part: Payments (about 28 hours).
Payment gateway integration | 10
Saved cards and UPI | 8
Receipts and refunds | 6
Failed payment handling | 4

Now do the same. Write only the answer lines.
Project: $title. ${desc.length > 240 ? desc.substring(0, 240) : desc}
Part: $part (about ${hours > 0 ? Todo.fmtHours(hours).replaceAll('h', '') : '20'} hours)${m.id == 'qwen3' ? ' /no_think' : ''}
''';
}

/// Budget and deliverables (modules with subtasks) the model suggests for a project.
class ProjectEstimate {
  final double budget;
  final List<Todo> todos;
  final bool fromRate; // budget = hours x the user's hourly rate (else the model guessed it)
  const ProjectEstimate(this.budget, this.todos, {this.fromRate = false});

  /// Same rule as [Project.hoursEstimate]: a module counts its subtasks' hours, or its own when it has none.
  double get hours => Project(todos: todos).hoursEstimate;

  /// Reads "budget 240000", module lines and "- task | hours" lines under them. Null when there is no task or no budget.
  static ProjectEstimate? parse(String text, {double rate = 0}) {
    final r = _scan(text, ai: true);
    final todos = r.todos..removeWhere((t) => t.sub.isEmpty && t.hoursValue == 0); // a module line with nothing under it
    if (todos.isEmpty) return null;
    final est = ProjectEstimate(0, todos);
    if (rate > 0) return ProjectEstimate((est.hours * rate).roundToDouble(), todos, fromRate: true);
    return r.budget == null || r.budget! <= 0 ? null : ProjectEstimate(r.budget!, todos);
  }

  /// Bulk add: one deliverable per line, "Name | hours" for its time, "- subtask" lines belong to the line above. Typed text, not model output,
  /// so nothing is treated as a budget line or a prompt echo and lines without hours are kept.
  static List<Todo> parseTasks(String text) => _scan(text, ai: false).todos;

  static ({double? budget, List<Todo> todos}) _scan(String text, {required bool ai}) {
    double? budget;
    final todos = <Todo>[];
    Todo? module; // the last module line; the "- task" lines after it are its subtasks
    final hoursRe = RegExp(r'^(.+?)\s*[|:\u2013\u2014-]\s*(\d+(?:\.\d+)?)\s*(?:h|hrs?|hours?)?\s*$', caseSensitive: false);
    final clean = ai ? text.replaceAll(RegExp(r'<think>[\s\S]*?(?:</think>|$)'), '').replaceAll(RegExp(r'```\w*'), '') : text;
    for (final raw in clean.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (ai) {
        if (RegExp(r'^(project|example|now do|notes?)\b', caseSensitive: false).hasMatch(line)) continue; // echoes of the prompt
        final b = RegExp(r'^budget\s*:?\s*[^\d]*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(line);
        if (b != null) {
          budget ??= double.tryParse(b.group(1)!.replaceAll(',', ''));
          continue;
        }
      }
      final isSub = RegExp(r'^[-*•]').hasMatch(line) || raw.startsWith(RegExp(r'\s{2,}'));
      final body = line.replaceFirst(RegExp(r'^[-*•]\s*'), '').replaceFirst(RegExp(r'^\d+[.)]\s+'), '');
      final g = ai ? RegExp(r'^(.+?)\s*(?:>|›|»)\s*(.+)$').firstMatch(body) : null; // "Module > task | hours"
      final m = hoursRe.firstMatch(g?.group(2) ?? body);
      final h = m == null ? null : double.tryParse(m.group(2)!);
      if (h != null && h > 0 && g != null) {
        final name = g.group(1)!.trim().toLowerCase();
        final parent = todos.where((t) => t.text.toLowerCase() == name).firstOrNull ?? (Todo(text: g.group(1)!.trim()));
        if (!todos.contains(parent)) todos.add(parent);
        parent.sub.add(Todo(text: m!.group(1)!.trim(), hours: Todo.fmtHours(h)));
        module = parent;
      } else if (h != null && h > 0) {
        final t = Todo(text: m!.group(1)!.trim(), hours: Todo.fmtHours(h));
        if (isSub && module != null) {
          module.sub.add(t);
        } else {
          todos.add(t);
          if (!isSub) module = t; // "Module | 40" followed by tasks: the tasks are its subtasks
        }
      } else if (isSub && module != null && !ai) {
        module.sub.add(Todo(text: body)); // a typed subtask without hours
      } else if (!isSub || !ai) {
        todos.add(module = Todo(text: body.replaceFirst(RegExp(r'[:\s]+$'), '')));
      }
    }
    return (budget: budget, todos: todos);
  }
}
