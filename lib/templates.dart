import 'models.dart';

// Document templates, the standard clause library, and the generator that turns a job description into the detailed sections of a
// quotation. Pure Dart (no Flutter), so it is shared by the builders, the PDF and the tests.

/// How a printed document looks. [look] picks the layout family drawn by pdf.dart and the thumbnails: 'classic', 'band', 'minimal'.
class DocTemplate {
  final String id, name, blurb, kind, look; // kind: 'invoice' | 'quote'
  final int accent; // 0xRRGGBB
  final List<String> clauses; // quotations: the clause ids switched on by default
  const DocTemplate(this.id, this.name, this.blurb, this.kind, this.look, this.accent, [this.clauses = const []]);
}

const invoiceTemplates = [
  DocTemplate('classic', 'Classic', 'Dark table header, orange accent', 'invoice', 'classic', 0xE4572E),
  DocTemplate('modern', 'Modern', 'Colour band across the top', 'invoice', 'band', 0x1F5F5B),
  DocTemplate('minimal', 'Minimal', 'Plain black and white, thin lines', 'invoice', 'minimal', 0x16140F),
];

const quoteTemplates = [
  DocTemplate('standard', 'Standard', 'Items, totals and key terms', 'quote', 'classic', 0x3B5B8C,
      ['payment', 'changes', 'ownership', 'cancellation', 'validity']),
  DocTemplate('proposal', 'Proposal', 'Full proposal: scope, timeline, payment plan, all terms', 'quote', 'band', 0x2B4A7A,
      ['assumptions', 'exclusions', 'payment', 'changes', 'ownership', 'confidentiality', 'cancellation', 'support', 'liability', 'disputes', 'validity']),
  DocTemplate('quick', 'Quick quote', 'One page: items and validity', 'quote', 'minimal', 0x16140F, ['validity', 'payment']),
];

DocTemplate templatesFor(String kind, String id) {
  final list = kind == 'invoice' ? invoiceTemplates : quoteTemplates;
  return list.firstWhere((t) => t.id == id, orElse: () => list.first); // the first of each kind is the original look
}

DocTemplate templateOf(Doc d) => templatesFor(d.kind, d.template);

// ------------------------------------------------------------------------------------------------------------ payment plans

class SchedulePreset {
  final String id, label;
  final List<(String, double)> steps;
  const SchedulePreset(this.id, this.label, this.steps);
  List<Milestone> build() => [for (final (l, p) in steps) Milestone(l, p)];
}

const schedulePresets = [
  SchedulePreset('end', '100% on delivery', [('On delivery', 100)]),
  SchedulePreset('half', '50% advance, 50% on delivery', [('Advance, on approval', 50), ('On delivery', 50)]),
  SchedulePreset('three', '40% / 30% / 30%', [('Advance, on approval', 40), ('Mid-project review', 30), ('On delivery', 30)]),
  SchedulePreset('upfront', '100% upfront', [('Upfront, on approval', 100)]),
];

// ------------------------------------------------------------------------------------------------------------ clause library

/// A standard clause. [id] is what templates and the builder refer to; the body is filled in by [clauseBody].
class Clause {
  final String id, title;
  const Clause(this.id, this.title);
}

const clauseLibrary = [
  Clause('assumptions', 'Assumptions'),
  Clause('exclusions', 'Exclusions'),
  Clause('payment', 'Payment terms'),
  Clause('changes', 'Revisions and changes'),
  Clause('ownership', 'Ownership'),
  Clause('confidentiality', 'Confidentiality'),
  Clause('cancellation', 'Cancellation'),
  Clause('support', 'Support after delivery'),
  Clause('liability', 'Limitation of liability'),
  Clause('disputes', 'Disputes'),
  Clause('validity', 'Validity'),
];

/// What the builder asks for besides the job description.
class QuoteSpec {
  String brief, clientName, bizName, paymentTerms;
  int revisions, validityDays;
  double latePct; // late payment charge per month, 0 = none
  Set<String> clauses;
  List<Todo> parts; // deliverables (with their features as subtasks) to describe in the scope and timeline
  DateTime date;
  QuoteSpec({
    this.brief = '',
    this.clientName = '',
    this.bizName = '',
    this.paymentTerms = 'Net 14',
    this.revisions = 2,
    this.validityDays = 30,
    this.latePct = 0,
    Set<String>? clauses,
    List<Todo>? parts,
    DateTime? date,
  })  : clauses = clauses ?? {},
        parts = parts ?? [],
        date = date ?? DateTime.now();
}

String clauseBody(String id, QuoteSpec s) {
  final biz = s.bizName.trim().isEmpty ? 'the service provider' : s.bizName.trim();
  final late = s.latePct > 0 ? ' Overdue amounts may carry a late charge of ${_n(s.latePct)}% per month.' : '';
  return switch (id) {
    'assumptions' => '- The client provides all content, brand assets, approvals and access needed, on time.\n'
        '- Feedback is gathered and shared through one point of contact.\n'
        '- The timeline starts once the first payment and all required inputs are received.\n'
        '- Third-party costs (domains, hosting, licences, stock assets, paid plugins) are not included unless listed above.',
    'exclusions' => '- Anything not listed under Scope of work.\n'
        '- Hosting, maintenance and support after hand-over, unless agreed in writing.\n'
        '- Legal, tax or compliance advice.\n'
        '- Data entry, content writing and translation, unless listed above.',
    'payment' => 'Payments follow the schedule in this quotation. Invoices are payable within ${s.paymentTerms.trim().isEmpty ? '14 days' : s.paymentTerms.trim()}. '
        'Work may be paused while an invoice is overdue.$late',
    'changes' => '- Up to ${s.revisions} ${s.revisions == 1 ? 'round' : 'rounds'} of revisions per deliverable ${s.revisions == 1 ? 'is' : 'are'} included.\n'
        '- Extra revisions and changes to the agreed scope are quoted before the work starts.\n'
        '- Changes are agreed in writing; a message or email is enough.',
    'ownership' => 'Ownership of the final deliverables passes to the client once they are paid for in full. Until then they remain the property of $biz. '
        '$biz may show the finished work in its portfolio unless the client asks in writing that it does not.',
    'confidentiality' => 'Both parties keep the other\'s non-public information confidential and use it only for this project.',
    'cancellation' => '- The client may cancel in writing at any time.\n'
        '- Work completed up to the cancellation date stays payable.\n'
        '- Any advance payment that has not been earned by work done is returned.',
    'support' => 'Defects in the delivered work that are reported within 30 days of hand-over are fixed free of charge. '
        'New features and changes after that are quoted separately.',
    'liability' => 'The total liability of $biz for this project is limited to the fees paid for it. Neither party is liable for indirect or consequential loss.',
    'disputes' => 'The parties first try to settle any disagreement by talking it through. If that fails, it is handled by the courts of the place where $biz is based.',
    'validity' => 'This quotation is valid for ${s.validityDays} days from ${fmtDate(s.date)}. Prices and timelines can change after that date.',
    _ => '',
  };
}

// ------------------------------------------------------------------------------------------------------------ the generator

/// Rough pace used to turn hours into weeks. ponytail: one fixed figure; make it a setting if people work at other paces.
const hoursPerWeek = 30.0;

int weeksFor(double hours) => hours <= 0 ? 1 : (hours / hoursPerWeek).ceil();

String _weeks(int w) => '$w ${w == 1 ? 'week' : 'weeks'}';

/// The detailed sections of a quotation: overview, scope, deliverables and features table, timeline, then the switched-on clauses.
List<DocSection> buildQuoteSections(QuoteSpec s) {
  final out = <DocSection>[];
  final brief = s.brief.trim();
  if (brief.isNotEmpty) {
    out.add(DocSection('Overview', '${s.clientName.trim().isEmpty ? '' : 'Prepared for ${s.clientName.trim()}.\n'}$brief'));
  }
  final parts = s.parts.where((t) => t.text.trim().isNotEmpty).toList();
  if (parts.isNotEmpty) {
    out.add(DocSection('Scope of work', [
      for (final t in parts) '- ${t.text.trim()}${t.sub.isEmpty ? '' : ': ${t.sub.map((x) => x.text.trim()).join(', ')}'}',
    ].join('\n')));
    if (parts.any((t) => t.sub.isNotEmpty)) {
      out.add(DocSection('Deliverables and features', [
        'Deliverable | Features included | Hours',
        for (final t in parts)
          '${t.text.trim()} | ${t.sub.isEmpty ? 'As described in the scope' : t.sub.map((x) => x.text.trim()).join(', ')} | ${_n(Project(todos: [t]).hoursEstimate)}',
      ].join('\n')));
    }
    final timed = parts.where((t) => Project(todos: [t]).hoursEstimate > 0).toList();
    if (timed.isNotEmpty) {
      var done = 0;
      final rows = <String>['Phase | Work | Duration'];
      for (final (i, t) in timed.indexed) {
        final w = weeksFor(Project(todos: [t]).hoursEstimate);
        done += w;
        rows.add('${i + 1} | ${t.text.trim()} | ${_weeks(w)}');
      }
      out.add(DocSection('Timeline', '${rows.join('\n')}\nEstimated total: ${_weeks(done)} from approval and receipt of the first payment.'));
    }
  }
  for (final c in clauseLibrary) {
    if (s.clauses.contains(c.id)) out.add(DocSection(c.title, clauseBody(c.id, s)));
  }
  return out;
}

/// A short title from a free-text brief: its first sentence or line, cut at 60 characters.
String titleFromBrief(String brief) {
  final first = brief.trim().split(RegExp(r'[\n.!?]')).first.trim();
  if (first.isEmpty) return '';
  final t = first.length > 60 ? '${first.substring(0, 57).trimRight()}…' : first;
  return t[0].toUpperCase() + t.substring(1);
}

// ------------------------------------------------------------------------------------------------------------ text blocks

sealed class DocBlock {}

class ParaBlock extends DocBlock {
  final String text;
  ParaBlock(this.text);
}

class BulletsBlock extends DocBlock {
  final List<String> items;
  BulletsBlock(this.items);
}

class TableBlock extends DocBlock {
  final List<String> header;
  final List<List<String>> rows;
  TableBlock(this.header, this.rows);
}

/// Reads a section body: runs of "- bullet" lines, runs of "a | b | c" lines (table, the first row is the header), other lines as paragraphs.
List<DocBlock> parseBlocks(String body) {
  final out = <DocBlock>[];
  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.contains(' | ')) {
      final cells = line.split('|').map((c) => c.trim()).toList();
      final last = out.isEmpty ? null : out.last;
      if (last is TableBlock) {
        last.rows.add(cells);
      } else {
        out.add(TableBlock(cells, []));
      }
    } else if (RegExp(r'^[-•*]\s+').hasMatch(line)) {
      final text = line.replaceFirst(RegExp(r'^[-•*]\s+'), '');
      final last = out.isEmpty ? null : out.last;
      if (last is BulletsBlock) {
        last.items.add(text);
      } else {
        out.add(BulletsBlock([text]));
      }
    } else {
      out.add(ParaBlock(line));
    }
  }
  return out;
}

/// 2 -> "2", 1.5 -> "1.5".
String _n(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// Amounts for a quotation's payment schedule. The last step takes whatever cents the rounding left, so they always add up to the total.
List<double> scheduleAmounts(Doc d) {
  final out = <double>[];
  var used = 0.0;
  for (final (i, m) in d.schedule.indexed) {
    final a = i == d.schedule.length - 1 ? round2(d.total - used) : round2(d.total * m.pct / 100);
    out.add(a);
    used += a;
  }
  return out;
}
