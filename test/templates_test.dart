import 'package:flutter_test/flutter_test.dart';
import 'package:freelance_os/models.dart';
import 'package:freelance_os/templates.dart';

List<Todo> _parts() => [
      Todo(text: 'Staff management', sub: [Todo(text: 'Staff profiles', hours: '16h'), Todo(text: 'Attendance', hours: '14h')]),
      Todo(text: 'Inventory', sub: [Todo(text: 'Stock list', hours: '40h')]),
    ];

void main() {
  test('every kind has a first template that is the original look', () {
    expect(templatesFor('invoice', '').id, 'classic');
    expect(templatesFor('quote', 'nope').id, 'standard');
    expect(templatesFor('invoice', 'modern').look, 'band');
    expect(templateOf(Doc(kind: 'quote', template: 'proposal')).name, 'Proposal');
  });

  test('buildQuoteSections writes overview, scope, features table, timeline and the chosen clauses in order', () {
    final spec = QuoteSpec(
      brief: 'CRM for a shop.',
      clientName: 'Paris Parker',
      bizName: 'Akshit Studio',
      parts: _parts(),
      clauses: {'validity', 'payment', 'changes'},
      revisions: 3,
      latePct: 2,
      validityDays: 15,
      date: DateTime(2026, 10, 12),
    );
    final s = buildQuoteSections(spec);
    expect(s.map((x) => x.title), ['Overview', 'Scope of work', 'Deliverables and features', 'Timeline', 'Payment terms', 'Revisions and changes', 'Validity']);
    expect(s[0].body, contains('Prepared for Paris Parker.'));
    expect(s[1].body, '- Staff management: Staff profiles, Attendance\n- Inventory: Stock list');
    expect(s[2].body, startsWith('Deliverable | Features included | Hours\nStaff management | Staff profiles, Attendance | 30'));
    expect(s[3].body, contains('1 | Staff management | 1 week'));
    expect(s[3].body, contains('2 | Inventory | 2 weeks'));
    expect(s[3].body, contains('Estimated total: 3 weeks'));
    expect(s[4].body, contains('late charge of 2% per month'));
    expect(s[5].body, contains('Up to 3 rounds of revisions'));
    expect(s[6].body, contains('valid for 15 days from 12 Oct 2026'));
  });

  test('with no deliverables only the overview and clauses are written', () {
    final s = buildQuoteSections(QuoteSpec(brief: 'Logo.', clauses: {'ownership'}));
    expect(s.map((x) => x.title), ['Overview', 'Ownership']);
    expect(s.last.body, contains('the service provider'));
  });

  test('parseBlocks groups bullets, tables and paragraphs', () {
    final b = parseBlocks('Intro line\n- one\n- two\nA | B\n1 | 2\n3 | 4\nTotal: 2');
    expect(b.length, 4);
    expect((b[0] as ParaBlock).text, 'Intro line');
    expect((b[1] as BulletsBlock).items, ['one', 'two']);
    final t = b[2] as TableBlock;
    expect(t.header, ['A', 'B']);
    expect(t.rows, [
      ['1', '2'],
      ['3', '4']
    ]);
    expect((b[3] as ParaBlock).text, 'Total: 2');
  });

  test('titleFromBrief takes the first sentence', () {
    expect(titleFromBrief('website for a bakery. five pages'), 'Website for a bakery');
    expect(titleFromBrief('   '), '');
    expect(titleFromBrief('x' * 100).length, 58);
  });

  test('schedule presets add up to 100', () {
    for (final p in schedulePresets) {
      expect(p.build().fold(0.0, (a, m) => a + m.pct), 100, reason: p.label);
    }
  });

  test('Doc keeps template, sections, schedule and line-item links through JSON', () {
    final d = Doc(
      kind: 'quote',
      template: 'proposal',
      sections: [DocSection('Scope', '- a')],
      schedule: [Milestone('On delivery', 100)],
      items: [LineItem(desc: 'x', todoId: 't9')],
    );
    final back = Doc.fromJson(d.toJson());
    expect(back.template, 'proposal');
    expect(back.sections.single.title, 'Scope');
    expect(back.schedule.single.pct, 100);
    expect(back.items.single.todoId, 't9');
    expect(Doc.fromJson({'kind': 'invoice'}).sections, isEmpty, reason: 'older saves have none');
    expect(LineItem(desc: 'y').toJson().containsKey('todoId'), isFalse);
  });
}
