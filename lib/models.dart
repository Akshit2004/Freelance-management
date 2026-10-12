import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'log.dart';

String money(double v) {
  final cur = store.profile.currency;
  final f = NumberFormat.decimalPatternDigits(locale: cur == '₹' ? 'en_IN' : 'en_US', decimalDigits: v % 1 == 0 ? 0 : 2);
  return '$cur${f.format(v)}';
}

/// Money is kept at 2 decimals everywhere (line, discount, tax, total) so the screen, the lists and the PDF always agree.
double round2(double v) => v.isFinite ? (v * 100).roundToDouble() / 100 : v;

String fmtDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String);

class Client {
  String id, name, company, email, phone, address, gstin, notes, initial;
  int colorValue;
  String contact; // optional contact person at the client
  Client({
    String? id,
    this.contact = '',
    this.name = '',
    this.company = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.gstin = '',
    this.notes = '',
    this.initial = '',
    int? colorValue,
  })  : id = id ?? newId(),
        colorValue = colorValue ?? 0xFF3B5B8C;

  String get ini => initial.isNotEmpty ? initial : (name.isNotEmpty ? name[0].toUpperCase() : 'C');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'company': company,
        'email': email,
        'phone': phone,
        'address': address,
        'gstin': gstin,
        'notes': notes,
        'initial': initial,
        'colorValue': colorValue,
        'contact': contact,
      };

  factory Client.fromJson(Map j) => Client(
        id: j['id'],
        name: j['name'] ?? '',
        company: j['company'] ?? '',
        email: j['email'] ?? '',
        phone: j['phone'] ?? '',
        address: j['address'] ?? '',
        gstin: j['gstin'] ?? '',
        notes: j['notes'] ?? '',
        initial: j['initial'] ?? '',
        colorValue: (j['colorValue'] as num?)?.toInt(),
        contact: j['contact'] ?? '',
      );

  Client copy() => Client.fromJson(toJson());
}

class Todo {
  String id, text, priority, hours;
  bool done;
  List<Todo> sub;
  Todo({
    String? id,
    required this.text,
    this.done = false,
    this.priority = 'med',
    this.hours = '',
    List<Todo>? sub,
  })  : id = id ?? newId(),
        sub = sub ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
        'priority': priority,
        'hours': hours,
        'sub': sub.map((s) => s.toJson()).toList(),
      };

  /// [hours] is stored as text ('14h', '1.5h'); this is the number in it (0 when empty or unreadable).
  double get hoursValue {
    final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(hours);
    return m == null ? 0 : double.tryParse(m.group(0)!.replaceAll(',', '.')) ?? 0;
  }

  /// 14 -> '14h', 1.5 -> '1.5h', 0 -> '' (what [hours] should hold for a number).
  static String fmtHours(double h) => h <= 0 ? '' : '${h % 1 == 0 ? h.toInt() : h}h';

  factory Todo.fromJson(Map j) => Todo(
        id: j['id'],
        text: j['text'] ?? '',
        done: j['done'] ?? false,
        priority: j['priority'] ?? 'med',
        hours: j['hours'] ?? '',
        sub: [for (final s in j['sub'] ?? []) Todo.fromJson(s)],
      );
}

const projectStatuses = ['active', 'review', 'done'];

class Project {
  String id, clientId, name, status, notes, next;
  double budget, spent;
  DateTime? deadline;
  List<Todo> todos;
  Project({
    String? id,
    this.clientId = '',
    this.name = '',
    this.status = 'active',
    this.notes = '',
    this.next = '',
    this.budget = 0,
    this.spent = 0,
    this.deadline,
    List<Todo>? todos,
  })  : id = id ?? newId(),
        todos = todos ?? [];

  List<Todo> get allLeaves {
    final list = <Todo>[];
    for (final t in todos) {
      if (t.sub.isNotEmpty) {
        list.addAll(t.sub);
      } else {
        list.add(t);
      }
    }
    return list;
  }

  double get progress {
    final leaves = allLeaves;
    if (leaves.isEmpty) return 0;
    return leaves.where((t) => t.done).length / leaves.length;
  }

  int get doneTasksCount => allLeaves.where((t) => t.done).length;
  int get totalTasksCount => allLeaves.length;

  /// Estimated hours across tasks; a task with subtasks counts its subtasks' hours (or its own when they have none).
  double get hoursEstimate => todos.fold(0.0, (s, t) {
        final sub = t.sub.fold(0.0, (a, b) => a + b.hoursValue);
        return s + (sub > 0 ? sub : t.hoursValue);
      });

  /// First unfinished task in list order (the subtask, when the task has subtasks).
  Todo? get nextTask => allLeaves.where((t) => !t.done).firstOrNull;

  /// Whole days from today to the deadline (negative = late); null without a deadline.
  int? daysLeft([DateTime? now]) {
    final d = deadline;
    if (d == null) return null;
    final n = now ?? DateTime.now();
    return DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
  }

  /// Not finished and past its deadline.
  bool isLate([DateTime? now]) => status != 'done' && (daysLeft(now) ?? 0) < 0;

  /// 'Due today', 'Due in 3 days', 'Due 15 Oct 2026', 'Overdue by 2 days'; null without a deadline.
  String? deadlineLabel([DateTime? now]) {
    final n = daysLeft(now);
    if (n == null) return null;
    if (n < 0) return 'Overdue by ${-n} ${n == -1 ? 'day' : 'days'}';
    if (n == 0) return 'Due today';
    if (n == 1) return 'Due tomorrow';
    return n <= 14 ? 'Due in $n days' : 'Due ${fmtDate(deadline!)}';
  }

  double get hoursTotal {
    double h = 0;
    for (final t in todos) {
      final s = t.hours.replaceAll(RegExp(r'[^0-9.]'), '');
      if (s.isNotEmpty) h += double.tryParse(s) ?? 0;
    }
    return h;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientId': clientId,
        'name': name,
        'status': status,
        'notes': notes,
        'next': next,
        'budget': budget,
        'spent': spent,
        'deadline': deadline?.toIso8601String(),
        'todos': todos.map((t) => t.toJson()).toList(),
      };

  factory Project.fromJson(Map j) => Project(
        id: j['id'],
        clientId: j['clientId'] ?? '',
        name: j['name'] ?? '',
        status: j['status'] ?? 'active',
        notes: j['notes'] ?? '',
        next: j['next'] ?? '',
        budget: _d(j['budget']),
        spent: _d(j['spent']),
        deadline: _date(j['deadline']),
        todos: [for (final t in j['todos'] ?? []) Todo.fromJson(t)],
      );

  Project copy() => Project.fromJson(toJson());
}

class LineItem {
  String desc, unit;
  double qty, rate;
  String? todoId; // the project deliverable this line was created from (null = typed by hand)
  LineItem({this.desc = '', this.qty = 1, this.rate = 0, this.unit = 'x', this.todoId});
  double get amount => round2(qty * rate);
  Map<String, dynamic> toJson() => {'desc': desc, 'qty': qty, 'rate': rate, 'unit': unit, if (todoId != null) 'todoId': todoId};
  factory LineItem.fromJson(Map j) =>
      LineItem(desc: j['desc'] ?? '', qty: _d(j['qty']), rate: _d(j['rate']), unit: j['unit'] ?? 'x', todoId: j['todoId']);
}

/// A titled block of text on a document, such as "Scope of work" or "Terms and conditions".
/// Body lines: "- text" is a bullet, lines with " | " form a table (first line is the header), anything else is a paragraph.
class DocSection {
  String title, body;
  DocSection(this.title, this.body);
  Map<String, dynamic> toJson() => {'title': title, 'body': body};
  factory DocSection.fromJson(Map j) => DocSection(j['title'] ?? '', j['body'] ?? '');
}

/// One payment in a quotation's schedule: [pct] percent of the total, due at [label] ("On approval", "On delivery").
class Milestone {
  String label;
  double pct;
  Milestone(this.label, this.pct);
  Map<String, dynamic> toJson() => {'label': label, 'pct': pct};
  factory Milestone.fromJson(Map j) => Milestone(j['label'] ?? '', _d(j['pct']));
}

/// Invoice and quotation share one shape; [kind] tells them apart.
class Doc {
  String id, kind, number, clientId, status, notes, title, terms;
  String? projectId, convertedToId;
  DateTime date, due;
  List<LineItem> items;
  double taxPct, discount;
  String template; // id from templates.dart; '' = the kind's default look
  List<DocSection> sections; // quotations: scope, timeline, terms ... printed after the totals
  List<Milestone> schedule; // quotations: when the money is due
  Doc({
    String? id,
    required this.kind,
    this.number = '',
    this.title = '',
    this.clientId = '',
    this.projectId,
    this.convertedToId,
    this.status = 'draft',
    this.notes = '',
    this.terms = 'Net 14',
    DateTime? date,
    DateTime? due,
    List<LineItem>? items,
    this.taxPct = 0,
    this.discount = 0,
    this.template = '',
    List<DocSection>? sections,
    List<Milestone>? schedule,
  })  : id = id ?? newId(),
        date = date ?? DateTime.now(),
        due = due ?? DateTime.now().add(const Duration(days: 15)),
        items = items ?? [],
        sections = sections ?? [],
        schedule = schedule ?? [];

  bool get isInvoice => kind == 'invoice';
  /// Statuses a user can store. 'overdue' is not one of them: it is derived ([overdue]) from 'sent' + a past due date.
  /// Older saves may still hold status 'overdue'; those load fine and show as overdue.
  List<String> get statuses => isInvoice ? ['draft', 'sent', 'paid'] : ['draft', 'sent', 'accepted', 'rejected'];
  double get subtotal => round2(items.fold(0.0, (s, i) => s + i.amount));
  double get discountAmount => round2(subtotal * discount / 100);
  double get taxable => round2((subtotal - discountAmount).clamp(0, double.infinity).toDouble());
  double get tax => round2(taxable * taxPct / 100);
  double get total => round2(taxable + tax);
  /// What to show in a badge: 'overdue' when derived/legacy overdue, otherwise the stored status.
  String get shownStatus => overdue ? 'overdue' : status;
  /// Sent and past its due *day* (an invoice due today is not overdue yet). Legacy stored 'overdue' still counts.
  bool get overdue {
    final n = DateTime.now();
    return isInvoice && (status == 'overdue' || (status == 'sent' && due.isBefore(DateTime(n.year, n.month, n.day))));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'number': number,
        'title': title,
        'clientId': clientId,
        'projectId': projectId,
        'convertedToId': convertedToId,
        'status': status,
        'notes': notes,
        'terms': terms,
        'date': date.toIso8601String(),
        'due': due.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
        'taxPct': taxPct,
        'discount': discount,
        'template': template,
        'sections': sections.map((x) => x.toJson()).toList(),
        'schedule': schedule.map((x) => x.toJson()).toList(),
      };

  factory Doc.fromJson(Map j) => Doc(
        id: j['id'],
        kind: j['kind'] ?? 'invoice',
        number: j['number'] ?? '',
        title: j['title'] ?? '',
        clientId: j['clientId'] ?? '',
        projectId: j['projectId'],
        convertedToId: j['convertedToId'],
        status: j['status'] ?? 'draft',
        notes: j['notes'] ?? '',
        terms: j['terms'] ?? 'Net 14',
        date: _date(j['date']),
        due: _date(j['due']),
        items: [for (final i in j['items'] ?? []) LineItem.fromJson(i)],
        taxPct: _d(j['taxPct']),
        discount: _d(j['discount']),
        template: j['template'] ?? '',
        sections: [for (final x in j['sections'] ?? []) DocSection.fromJson(x)],
        schedule: [for (final x in j['schedule'] ?? []) Milestone.fromJson(x)],
      );

  Doc copy() => Doc.fromJson(toJson());
}

class Profile {
  String bizName, ownerName, email, phone, address, gstin, upi, bank, currency, terms, aiModel, taxId;
  double defaultTax;
  double hourlyRate; // used by AI estimates: budget = estimated hours x this (0 = let the model guess a price)
  int dueDays;
  String hardware; // 'GPU' or 'CPU'
  bool heuristicFallback;
  int lastBackupRev; // Store.rev at the time of the last backup
  bool autoBackup; // upload to MongoDB when the app goes to the background and something changed
  bool liveMode; // Magic re-reads the notes with the model after every pause in typing
  DateTime? lastBackup; // when the user last exported a backup (null = never)
  int lastBackupBytes;

  Profile({
    this.lastBackup,
    this.lastBackupBytes = 0,
    this.bizName = '',
    this.ownerName = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.gstin = '',
    this.taxId = '',
    this.upi = '',
    this.bank = '',
    this.currency = '₹',
    this.terms = 'Thank you for your business.',
    this.aiModel = '',
    this.defaultTax = 0,
    this.hourlyRate = 0,
    this.dueDays = 14,
    this.hardware = 'GPU',
    this.heuristicFallback = false,
    this.liveMode = false,
    this.autoBackup = false,
    this.lastBackupRev = 0,
  });

  Map<String, dynamic> toJson() => {
        'bizName': bizName,
        'ownerName': ownerName,
        'email': email,
        'phone': phone,
        'address': address,
        'gstin': gstin,
        'taxId': taxId,
        'upi': upi,
        'bank': bank,
        'currency': currency,
        'terms': terms,
        'aiModel': aiModel,
        'defaultTax': defaultTax,
        'hourlyRate': hourlyRate,
        'dueDays': dueDays,
        'hardware': hardware,
        'heuristicFallback': heuristicFallback,
        'liveMode': liveMode,
        'autoBackup': autoBackup,
        'lastBackupRev': lastBackupRev,
        'lastBackup': lastBackup?.toIso8601String(),
        'lastBackupBytes': lastBackupBytes,
      };

  factory Profile.fromJson(Map j) => Profile(
        bizName: j['bizName'] ?? '',
        ownerName: j['ownerName'] ?? '',
        email: j['email'] ?? '',
        phone: j['phone'] ?? '',
        address: j['address'] ?? '',
        gstin: j['gstin'] ?? '',
        taxId: j['taxId'] ?? j['gstin'] ?? '', // one tax-id field now; older saves kept it as gstin
        upi: j['upi'] ?? '',
        bank: j['bank'] ?? '',
        currency: j['currency'] ?? '₹',
        terms: j['terms'] ?? 'Thank you for your business.',
        aiModel: j['aiModel'] ?? '',
        defaultTax: _d(j['defaultTax']),
        hourlyRate: _d(j['hourlyRate']),
        dueDays: j['dueDays'] ?? 14,
        hardware: j['hardware'] ?? 'GPU',
        heuristicFallback: j['heuristicFallback'] ?? false,
        liveMode: j['liveMode'] ?? false,
        autoBackup: j['autoBackup'] ?? false,
        lastBackupRev: (j['lastBackupRev'] as num?)?.toInt() ?? 0,
        lastBackup: _date(j['lastBackup']),
        lastBackupBytes: (j['lastBackupBytes'] as num?)?.toInt() ?? 0,
      );
}

/// One line in the Home feed. [tone]: good (money in / done), info, bad, dim.
class Activity {
  final String id, text, tone;
  final DateTime at;
  Activity({String? id, required this.text, this.tone = 'dim', DateTime? at})
      : id = id ?? newId(),
        at = at ?? DateTime.now();
  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'tone': tone, 'at': at.toIso8601String()};
  factory Activity.fromJson(Map j) =>
      Activity(id: j['id'], text: j['text'] ?? '', tone: j['tone'] ?? 'dim', at: _date(j['at']));
}

String _kb(int bytes) => bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';

final store = Store();

/// Everything lives in one JSON file. ponytail: whole-file rewrite per save, fine for thousands of docs; move to sqlite if it lags.
class Store extends ChangeNotifier {
  List<Client> clients = [];
  List<Project> projects = [];
  List<Doc> docs = [];
  Profile profile = Profile();
  List<Activity> activity = [];
  File? _file;
  Future<void> _writing = Future.value();
  Timer? _debounce;

  Future<void> load() async {
    _file = File('${(await getApplicationDocumentsDirectory()).path}/freelance_os.json');
    final sw = Stopwatch()..start();
    if (await _file!.exists()) {
      try {
        final text = await _file!.readAsString();
        final j = jsonDecode(text);
        clients = [for (final c in j['clients'] ?? []) Client.fromJson(c)];
        projects = [for (final p in j['projects'] ?? []) Project.fromJson(p)];
        docs = [for (final d in j['docs'] ?? []) Doc.fromJson(d)];
        profile = Profile.fromJson(j['profile'] ?? {});
        activity = [for (final a in j['activity'] ?? []) Activity.fromJson(a)];
        rev = (j['rev'] as num?)?.toInt() ?? 0;
        Log.db('read   freelance_os.json  ${_kb(text.length)}  ${clients.length} clients, ${projects.length} projects, ${docs.length} docs  ${sw.elapsedMilliseconds} ms');
      } catch (e) {
        Log.db('read   freelance_os.json FAILED ($e), keeping the data already in memory');
      }
    } else {
      Log.db('read   no database file yet, starting empty');
    }
    _purgeDemoData();
    baseline();
  }

  // ---- activity feed: compares the data against the last saved state, so every screen that calls save() is covered.
  // ponytail: only logs on save(); an invoice turning overdue as time passes isn't an event until something is saved.
  final _status = <String, String>{}; // 'd:<id>' / 'p:<id>' / 'c:<id>' -> status
  final _label = <String, String>{}; // same keys -> display name
  final _done = <String, Set<String>>{}; // project id -> ids of completed tasks

  void _scan() {
    _status.clear();
    _label.clear();
    _done.clear();
    for (final d in docs) {
      _status['d:${d.id}'] = d.status;
      _label['d:${d.id}'] = d.number;
    }
    for (final p in projects) {
      _status['p:${p.id}'] = p.status;
      _label['p:${p.id}'] = p.name;
      _done[p.id] = {for (final t in p.allLeaves) if (t.done) t.id};
    }
    for (final c in clients) {
      _status['c:${c.id}'] = '';
      _label['c:${c.id}'] = c.name;
    }
  }

  void baseline() => _scan();

  void _log(String text, String tone) {
    activity.insert(0, Activity(text: text, tone: tone));
    if (activity.length > 60) activity.removeRange(60, activity.length);
  }

  void _diff() {
    final oldStatus = Map.of(_status), oldLabel = Map.of(_label), oldDone = Map.of(_done);
    for (final c in clients) {
      if (!oldStatus.containsKey('c:${c.id}')) _log('New client · ${c.name}', 'info');
    }
    for (final p in projects) {
      final old = oldStatus['p:${p.id}'];
      final who = clientName(p.clientId);
      if (old == null) {
        _log('Project "${p.name}" started for $who', 'info');
        continue;
      }
      if (old != p.status) {
        _log(
            switch (p.status) {
              'done' => 'Project "${p.name}" completed',
              'review' => 'Project "${p.name}" moved to review',
              _ => 'Project "${p.name}" is active again',
            },
            p.status == 'done' ? 'good' : 'info');
      }
      final before = oldDone[p.id] ?? {};
      for (final t in p.allLeaves) {
        if (t.done && !before.contains(t.id)) _log('Done · ${t.text} (${p.name})', 'good');
      }
    }
    for (final d in docs) {
      final old = oldStatus['d:${d.id}'];
      final who = clientName(d.clientId);
      if (old == null) {
        _log('${d.number} drafted for $who', 'info');
      } else if (old != d.status) {
        final (text, tone) = switch (d.status) {
          'paid' => ('${d.number} paid by $who · ${money(d.total)}', 'good'),
          'sent' => ('${d.number} sent to $who', 'info'),
          'accepted' => ('${d.number} accepted by $who', 'good'),
          'rejected' => ('${d.number} rejected by $who', 'bad'),
          'overdue' => ('${d.number} is overdue · $who', 'bad'),
          _ => ('${d.number} moved back to draft', 'dim'),
        };
        _log(text, tone);
      }
    }
    for (final k in oldStatus.keys) {
      final gone = switch (k[0]) {
        'd' => !docs.any((d) => 'd:${d.id}' == k),
        'p' => !projects.any((p) => 'p:${p.id}' == k),
        _ => !clients.any((c) => 'c:${c.id}' == k),
      };
      if (gone) _log('Deleted · ${oldLabel[k]}', 'dim');
    }
    _scan();
  }

  /// Pull-to-refresh: waits for any pending write, then re-reads the file (keeps current data if it can't be parsed).
  Future<void> reload() async {
    Log.db('reload from disk (pull to refresh)');
    await _writing;
    await load();
    notifyListeners();
  }

  /// The whole database as JSON (also what a backup file contains).
  String exportJson() => jsonEncode({
        'app': 'hustler',
        'version': 1,
        'rev': rev,
        'clients': clients.map((c) => c.toJson()).toList(),
        'projects': projects.map((p) => p.toJson()).toList(),
        'docs': docs.map((d) => d.toJson()).toList(),
        'profile': profile.toJson(),
        'activity': activity.map((a) => a.toJson()).toList(),
      });

  /// Replaces everything with a backup. Returns null on success, or a human-readable reason it was rejected (nothing is changed then).
  Future<String?> restoreJson(String text) async {
    Log.db('restore backup (${_kb(text.length)})');
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['clients'] is! List || j['projects'] is! List || j['docs'] is! List) return 'This is not a Hustler backup file.';
      final c = [for (final x in j['clients']) Client.fromJson(x)];
      final p = [for (final x in j['projects']) Project.fromJson(x)];
      final d = [for (final x in j['docs']) Doc.fromJson(x)];
      final pr = Profile.fromJson(j['profile'] ?? {});
      final a = [for (final x in j['activity'] ?? []) Activity.fromJson(x)];
      clients = c;
      projects = p;
      docs = d;
      profile = pr;
      activity = a;
    } catch (_) {
      return 'The file is damaged or from a different app.';
    }
    baseline();
    await save(); // counts as a change (rev goes up)
    return null;
  }

  /// Size of the data file on disk, for the Settings screen.
  Future<int> dataBytes() async => (_file != null && await _file!.exists()) ? _file!.length() : 0;

  /// Fixed ids the old design preview shipped as sample data. Real records use time-based ids, so these are never yours.
  static const _demoClients = {'c1', 'c2', 'c3', 'c4'};
  static const _demoProjects = {'p1', 'p2', 'p3', 'p4'};
  static final _demoDocs = {for (var i = 1; i <= 10; i++) 'd$i'};

  void _purgeDemoData() {
    final had = clients.any((c) => _demoClients.contains(c.id)) || docs.any((d) => _demoDocs.contains(d.id));
    if (!had) return;
    clients.removeWhere((c) => _demoClients.contains(c.id));
    projects.removeWhere((p) => _demoProjects.contains(p.id));
    docs.removeWhere((d) => _demoDocs.contains(d.id));
    activity = [];
    final sample = profile.bizName == 'Okafor Studio';
    if (sample) profile = Profile(currency: profile.currency, aiModel: profile.aiModel, hardware: profile.hardware, heuristicFallback: profile.heuristicFallback, liveMode: profile.liveMode, autoBackup: profile.autoBackup, lastBackupRev: profile.lastBackupRev);
    Future.microtask(save);
  }

  /// Notifies listeners, then writes to a temp file and renames so a crash mid-write can't corrupt data.
  Future<void> save() {
    if (!_recordingBackup) rev++;
    _diff();
    notifyListeners();
    final f = _file;
    if (f == null) return Future.value();
    final data = exportJson();
    return _writing = _writing.then((_) async {
      final sw = Stopwatch()..start();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(f.path);
      Log.db('write  freelance_os.json  ${_kb(data.length)}  ${clients.length} clients, ${projects.length} projects, ${docs.length} docs  ${sw.elapsedMilliseconds} ms');
    });
  }

  // ---- backup bookkeeping
  int rev = 0; // bumped on every real change; saved with the data, so it survives restarts
  bool _recordingBackup = false;

  /// Something changed since the last backup (or there never was one while data exists).
  bool get needsBackup {
    if (profile.lastBackup == null) return clients.isNotEmpty || projects.isNotEmpty || docs.isNotEmpty;
    return rev > profile.lastBackupRev;
  }

  /// Records that a backup of [bytes] was just made, without counting that bookkeeping as a data change.
  void markBackedUp(int bytes) {
    _recordingBackup = true;
    profile.lastBackup = DateTime.now();
    profile.lastBackupBytes = bytes;
    profile.lastBackupRev = rev;
    save();
    _recordingBackup = false;
  }

  /// Write after typing stops. Use for text fields so a keystroke doesn't rewrite the file.
  void saveSoon() {
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), save);
  }

  /// Clears write bookkeeping between tests (a debounce timer from one test must not leak into the next).
  @visibleForTesting
  void debugReset() {
    _debounce?.cancel();
    _debounce = null;
    _writing = Future.value();
    _recordingBackup = false;
    rev = 0;
  }

  /// Makes sure nothing is waiting to be written (call when the app goes to the background).
  Future<void> flush() async {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      await save();
    }
    await _writing;
  }

  // ---- intents: screens call these instead of editing models and calling save() themselves.
  Doc? doc(String? id) => docs.where((d) => d.id == id).firstOrNull;

  /// Runs [change] then saves. Escape hatch for edits that don't have their own intent yet.
  void mutate(void Function() change) {
    Log.db('update (edit)');
    change();
    save();
  }

  void updateProfile(void Function(Profile p) edit) {
    Log.db('update profile');
    edit(profile);
    saveSoon();
  }

  void setDocStatus(String id, String status) {
    Log.db('update doc $id  status -> $status');
    final d = doc(id);
    if (d == null || d.status == status || !d.statuses.contains(status)) return; // 'overdue' is derived, never stored
    d.status = status;
    save();
  }

  void setProjectStatus(String id, String status) {
    Log.db('update project $id  status -> $status');
    final p = project(id);
    if (p == null || p.status == status) return;
    p.status = status;
    save();
  }

  void toggleTodo(String projectId, String todoId) {
    Log.db('update task $todoId  toggle done');
    final t = project(projectId)?.todos.where((t) => t.id == todoId).firstOrNull;
    if (t == null) return;
    t.done = !t.done;
    for (final s in t.sub) {
      s.done = t.done;
    }
    save();
  }

  void toggleSub(String projectId, String parentId, String subId) {
    Log.db('update subtask $subId  toggle done');
    final parent = project(projectId)?.todos.where((t) => t.id == parentId).firstOrNull;
    final sub = parent?.sub.where((s) => s.id == subId).firstOrNull;
    if (parent == null || sub == null) return;
    sub.done = !sub.done;
    parent.done = parent.sub.every((s) => s.done);
    save();
  }

  void addTodo(String projectId, Todo todo) {
    Log.db('insert task in project $projectId');
    final p = project(projectId);
    if (p == null) return;
    p.todos.add(todo);
    save();
  }

  /// Saves an AI estimate: sets the budget and adds its deliverables (ones already listed by name are skipped).
  void applyEstimate(String projectId, double budget, List<Todo> todos) {
    Log.db('update project $projectId  AI estimate');
    final p = project(projectId);
    if (p == null) return;
    final have = {for (final t in p.todos) t.text.trim().toLowerCase()};
    p.budget = budget;
    p.todos.addAll(todos.where((t) => have.add(t.text.trim().toLowerCase())));
    save();
  }

  /// Changes a task or subtask's text / priority / hours (null = leave as is).
  void editTodo(String projectId, String todoId, {String? text, String? priority, String? hours}) {
    Log.db('update task $todoId');
    final t = _findTodo(project(projectId), todoId)?.$2;
    if (t == null) return;
    if (text != null) t.text = text;
    if (priority != null) t.priority = priority;
    if (hours != null) t.hours = hours;
    save();
  }

  /// Adds several deliverables at once (bulk add). One save.
  void addTodos(String projectId, List<Todo> todos) {
    Log.db('insert ${todos.length} tasks in project $projectId');
    final p = project(projectId);
    if (p == null || todos.isEmpty) return;
    p.todos.addAll(todos);
    save();
  }

  /// Removes several deliverables (with their subtasks) at once (bulk remove). One save.
  void deleteTodos(String projectId, Set<String> ids) {
    Log.db('delete ${ids.length} tasks in project $projectId');
    final p = project(projectId);
    if (p == null || ids.isEmpty) return;
    p.todos.removeWhere((t) => ids.contains(t.id));
    save();
  }

  /// Numbers of the documents that have a line created from this deliverable ("QT-3"), for the "Quoted" tag.
  List<String> quotedIn(String todoId) => [for (final d in docs) if (d.items.any((i) => i.todoId == todoId)) d.number];

  /// Removes a task (with its subtasks) or a single subtask.
  void deleteTodo(String projectId, String todoId) {
    Log.db('delete task $todoId');
    final p = project(projectId);
    final found = _findTodo(p, todoId);
    if (p == null || found == null) return;
    final (parent, t) = found;
    final list = parent == null ? p.todos : parent.sub;
    list.remove(t);
    if (parent != null && parent.sub.isNotEmpty) parent.done = parent.sub.every((s) => s.done);
    save();
  }

  /// Adds a subtask; the parent is no longer complete.
  void addSub(String projectId, String parentId, Todo sub) {
    Log.db('insert subtask in task $parentId');
    final parent = project(projectId)?.todos.where((t) => t.id == parentId).firstOrNull;
    if (parent == null) return;
    parent.sub.add(sub);
    parent.done = false;
    save();
  }

  (Todo?, Todo)? _findTodo(Project? p, String id) {
    for (final t in p?.todos ?? const <Todo>[]) {
      if (t.id == id) return (null, t);
      for (final s in t.sub) {
        if (s.id == id) return (t, s);
      }
    }
    return null;
  }

  /// Documents (invoices and quotes) linked to a project, newest first as stored.
  List<Doc> docsOfProject(String projectId) => docs.where((d) => d.projectId == projectId).toList();

  /// Total of the project's invoices that have gone out (sent, paid or overdue; drafts don't count).
  double projectInvoiced(String projectId) =>
      invoices.where((d) => d.projectId == projectId && d.status != 'draft').fold(0, (s, d) => s + d.total);

  /// Total of the project's invoices marked paid.
  double projectPaid(String projectId) =>
      invoices.where((d) => d.projectId == projectId && d.status == 'paid').fold(0, (s, d) => s + d.total);

  /// True when the user hasn't filled in who they are yet (Home nudges them to Settings).
  bool get needsSetup => profile.bizName.trim().isEmpty && profile.ownerName.trim().isEmpty;

  Client? client(String? id) => clients.where((c) => c.id == id).firstOrNull;
  Project? project(String? id) => projects.where((p) => p.id == id).firstOrNull;
  String clientName(String? id) => client(id)?.name ?? 'Unknown client';

  void _upsert<T>(List<T> list, T item, String Function(T) id) {
    final i = list.indexWhere((x) => id(x) == id(item));
    Log.db('${i < 0 ? 'insert' : 'update'} ${T.toString().toLowerCase()} ${id(item)}');
    i < 0 ? list.insert(0, item) : list[i] = item;
    save();
  }

  void putClient(Client c) => _upsert(clients, c, (x) => x.id);
  void putProject(Project p) => _upsert(projects, p, (x) => x.id);
  void putDoc(Doc d) => _upsert(docs, d, (x) => x.id);

  /// Returns false if the client still has documents (financial records are never cascaded away).
  bool deleteClient(String id) {
    Log.db('delete client $id');
    if (docs.any((d) => d.clientId == id)) return false;
    clients.removeWhere((c) => c.id == id);
    projects.removeWhere((p) => p.clientId == id);
    save();
    return true;
  }

  void deleteProject(String id) {
    Log.db('delete project $id');
    projects.removeWhere((p) => p.id == id);
    for (final d in docs.where((d) => d.projectId == id)) {
      d.projectId = null;
    }
    save();
  }

  void deleteDoc(String id) {
    Log.db('delete doc $id');
    docs.removeWhere((d) => d.id == id);
    for (final q in docs.where((q) => q.convertedToId == id)) {
      q.convertedToId = null; // the invoice is gone, so the quote can be converted again
    }
    save();
  }

  /// INV-2026-007 style; uses max existing + 1 so deletions never cause duplicates.
  String nextNumber(String kind, [DateTime? at]) {
    final prefix = '${kind == 'invoice' ? 'INV' : 'QT'}-${(at ?? DateTime.now()).year}-';
    final n = docs
        .where((d) => d.number.startsWith(prefix))
        .map((d) => int.tryParse(d.number.substring(prefix.length)) ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    return '$prefix${(n + 1).toString().padLeft(3, '0')}';
  }

  Doc newDoc(String kind, {String clientId = '', String? projectId}) => Doc(
      kind: kind, number: nextNumber(kind), clientId: clientId, projectId: projectId, taxPct: profile.defaultTax,
      due: DateTime.now().add(Duration(days: kind == 'invoice' ? profile.dueDays : 30)), notes: profile.terms,
      terms: kind == 'invoice' && profile.dueDays <= 0 ? 'Due on receipt' : 'Net ${kind == 'invoice' ? profile.dueDays : 14}');

  /// Turns a quote into an invoice once: converting again returns the invoice that already exists.
  Doc quoteToInvoice(Doc q) {
    Log.db('convert quote ${q.number} to invoice');
    final existing = doc(q.convertedToId);
    if (existing != null) return existing;
    q.status = 'accepted';
    final inv = newDoc('invoice', clientId: q.clientId, projectId: q.projectId)
      ..title = q.title
      ..items = [for (final i in q.items) LineItem.fromJson(i.toJson())]
      ..taxPct = q.taxPct
      ..discount = q.discount;
    q.convertedToId = inv.id;
    docs.insert(0, inv);
    save();
    return inv;
  }

  Iterable<Doc> get invoices => docs.where((d) => d.isInvoice);
  double get paid => invoices.where((d) => d.status == 'paid').fold(0, (s, d) => s + d.total);
  /// Unpaid money out in the world: sent invoices, including ones that are past due (and old saves that stored 'overdue').
  double get outstanding => invoices.where((d) => d.status == 'sent' || d.status == 'overdue').fold(0, (s, d) => s + d.total);
  double get pipeline => docs.where((d) => !d.isInvoice && d.status == 'sent').fold(0, (s, d) => s + d.total);
  int get overdueCount => docs.where((d) => d.overdue).length;
  double billedTo(String clientId) => invoices.where((d) => d.clientId == clientId).fold(0, (s, d) => s + d.total);
}
