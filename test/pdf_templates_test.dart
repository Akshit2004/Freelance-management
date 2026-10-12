import 'package:flutter_test/flutter_test.dart';
import 'package:freelance_os/models.dart';
import 'package:freelance_os/pdf.dart';
import 'package:freelance_os/templates.dart';

import 'harness.dart';

String _text(List<int> b) => String.fromCharCodes(b);
int _pages(List<int> b) => RegExp(r'/Type\s*/Page(?!s)').allMatches(_text(b)).length;

Doc _quote({String template = '', bool detailed = true}) {
  final parts = [
    Todo(text: 'Staff management', sub: [Todo(text: 'Staff profiles', hours: '16h'), Todo(text: 'Attendance and shifts', hours: '14h')]),
    Todo(text: 'Inventory', sub: [Todo(text: 'Stock list', hours: '40h'), Todo(text: 'Purchase orders', hours: '30h')]),
    Todo(text: 'Invoicing', sub: [Todo(text: 'Invoice builder', hours: '24h')]),
  ];
  final spec = QuoteSpec(
    brief: 'A CRM for a retail shop with staff, stock and billing. ${'It must work offline. ' * 6}',
    clientName: 'Paris Parker',
    bizName: 'Okafor Studio',
    parts: parts,
    clauses: templatesFor('quote', template).clauses.toSet(),
  );
  return Doc(
    kind: 'quote',
    number: 'QT-1',
    title: 'Paris Parker CRM',
    clientId: 'c1',
    template: template,
    taxPct: 18,
    items: [for (final t in parts) LineItem(desc: t.text, qty: Project(todos: [t]).hoursEstimate, unit: 'h', rate: 800, todoId: t.id)],
    sections: detailed ? buildQuoteSections(spec) : [],
    schedule: detailed ? schedulePresets[2].build() : [],
  );
}

void main() {
  setUp(() {
    resetStore();
    store.profile = Profile(bizName: 'Okafor Studio', ownerName: 'Ada Okafor', email: 'ada@okafor.studio', currency: '₹', upi: 'ada@upi', bank: 'HDFC Bank\nA/C 123');
    store.clients = [Client(id: 'c1', name: 'Paris Parker', email: 'paris@parker.test')];
  });

  testWidgets('every invoice template renders a PDF', (t) async {
    sizes() async {
      final out = <String, int>{};
      for (final tpl in invoiceTemplates) {
        final d = Doc(kind: 'invoice', number: 'INV-1', clientId: 'c1', template: tpl.id, status: 'sent', taxPct: 18, items: [LineItem(desc: 'Build', qty: 10, rate: 2500, unit: 'hrs')]);
        final b = await t.runAsync(() => buildPdf(d));
        expect(_text(b!.take(5).toList()), '%PDF-', reason: tpl.id);
        out[tpl.id] = b.length;
      }
      return out;
    }

    final s = await sizes();
    expect(s.values.toSet().length, greaterThan(1), reason: 'templates must draw different documents');
    // a paid invoice draws the paid mark in every look
    for (final tpl in invoiceTemplates) {
      final b = await t.runAsync(() => buildPdf(Doc(kind: 'invoice', number: 'I', clientId: 'c1', template: tpl.id, status: 'paid', items: [LineItem(desc: 'a', rate: 5)])));
      expect(_text(b!.take(5).toList()), '%PDF-', reason: '${tpl.id} paid');
    }
  });

  testWidgets('a detailed quotation (sections, schedule, signatures) renders in every quote template and is longer than a bare one', (t) async {
    for (final tpl in quoteTemplates) {
      final bare = await t.runAsync(() => buildPdf(_quote(template: tpl.id, detailed: false)));
      final full = await t.runAsync(() => buildPdf(_quote(template: tpl.id)));
      expect(_text(full!.take(5).toList()), '%PDF-', reason: tpl.id);
      expect(full.length, greaterThan(bare!.length), reason: '${tpl.id} adds the sections');
    }
    final proposal = await t.runAsync(() => buildPdf(_quote(template: 'proposal')));
    expect(_pages(proposal!), greaterThanOrEqualTo(2), reason: 'a full proposal spans pages');
  });

  testWidgets('an unknown template id falls back to the original look and old documents still render', (t) async {
    final b = await t.runAsync(() => buildPdf(Doc(kind: 'invoice', number: 'I', template: 'does-not-exist', items: [LineItem(desc: 'a', rate: 5)])));
    expect(_text(b!.take(5).toList()), '%PDF-');
    final old = Doc.fromJson({'kind': 'quote', 'number': 'Q', 'items': []});
    expect(_text((await t.runAsync(() => buildPdf(old)))!.take(5).toList()), '%PDF-');
  });

  test('scheduleAmounts always adds up to the total', () {
    final d = Doc(kind: 'quote', items: [LineItem(desc: 'x', qty: 3, rate: 33.33)], schedule: [Milestone('a', 33.3), Milestone('b', 33.3), Milestone('c', 33.4)]);
    final a = scheduleAmounts(d);
    expect(a.fold(0.0, (x, y) => x + y), closeTo(d.total, 0.001));
  });
}
