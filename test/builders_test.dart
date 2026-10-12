import 'package:flutter/material.dart';
import 'package:freelance_os/builder_widgets.dart';
import 'package:freelance_os/builders.dart';
import 'package:freelance_os/docs.dart';
import 'package:freelance_os/models.dart';
import 'package:freelance_os/projects.dart';
import 'package:freelance_os/templates.dart';

import 'harness.dart';

const tall = Size(360, 3200); // everything built at once

void _seed({double rate = 1000}) {
  resetStore();
  store.profile = Profile(bizName: 'Okafor Studio', currency: '₹', hourlyRate: rate, defaultTax: 18, dueDays: 14);
  store.clients = [Client(id: 'c1', name: 'Acme Corp')];
  store.projects = [
    Project(id: 'p1', clientId: 'c1', name: 'CRM', todos: [
      Todo(id: 't1', text: 'Staff management', hours: '10h', done: true),
      Todo(id: 't2', text: 'Inventory', sub: [Todo(id: 's1', text: 'Stock list', hours: '8h'), Todo(id: 's2', text: 'Purchase orders', hours: '12h')]),
      Todo(id: 't3', text: 'Reports'),
    ]),
  ];
}

Doc _quote({String id = 'q1'}) => Doc(
      id: id,
      kind: 'quote',
      number: 'QT-2026-001',
      title: 'CRM build',
      clientId: 'c1',
      projectId: 'p1',
      status: 'sent',
      taxPct: 18,
      items: [LineItem(desc: 'Build', qty: 10, unit: 'h', rate: 1000)],
      schedule: schedulePresets[1].build(),
    );

/// Scrolls a long page top to bottom so every lazily built part gets laid out once (overflows surface through takeException).
Future<void> _scrollAll(WidgetTester t) async {
  final list = find.byType(ListView).first;
  for (var i = 0; i < 24; i++) {
    await t.drag(list, const Offset(0, -260));
    await t.pump();
  }
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.pump(); // apply the scroll before the tap reads the widget's position
  await t.tap(find.byKey(Key(key)));
  await settle(t);
}

void main() {
  group('Quotation builder', () {
    testWidgets('picks deliverables, adds an item, writes the sections and schedule, and links lines to deliverables', (t) async {
      _seed();
      await pumpScreen(t, const QuoteBuilderPage(clientId: 'c1', projectId: 'p1'), size: tall);
      expect(find.text('New quotation'), findsOneWidget);
      await t.enterText(find.byKey(const Key('quote-brief')), 'A CRM for a shop. It must work offline.');
      await t.enterText(find.byKey(const Key('quote-title')), 'Shop CRM');

      await _tap(t, 'quote-from-deliverables');
      expect(find.text('Add from deliverables'), findsOneWidget);
      await t.tap(find.byKey(const Key('pick-all')));
      await t.pump();
      expect(find.text('Add 3 deliverables'), findsOneWidget);
      await t.tap(find.byKey(const Key('pick-confirm')));
      await settle(t);
      expect(find.byKey(const Key('line-0')), findsOneWidget);
      expect(find.byKey(const Key('line-2')), findsOneWidget);
      expect(find.textContaining('10 h × ₹1,000'), findsOneWidget); // Staff management: its hours at the hourly rate
      expect(find.textContaining('20 h × ₹1,000'), findsOneWidget); // Inventory: sum of its features

      await _tap(t, 'quote-new-item');
      await t.enterText(find.byKey(const Key('line-desc')), 'Training day');
      await t.enterText(find.byKey(const Key('line-qty')), '2');
      await t.enterText(find.byKey(const Key('line-rate')), '4000');
      await t.tap(find.byKey(const Key('line-save')));
      await settle(t);
      expect(find.byKey(const Key('line-3')), findsOneWidget);

      // sections are previewed live
      expect(find.byKey(const Key('preview-Overview')), findsOneWidget);
      expect(find.byKey(const Key('preview-Scope of work')), findsOneWidget);
      expect(find.byKey(const Key('preview-Timeline')), findsOneWidget);
      expect(find.byKey(const Key('preview-Payment terms')), findsOneWidget);

      await _tap(t, 'quote-create');
      expect(t.takeException(), isNull);
      final q = store.docs.single;
      expect(q.kind, 'quote');
      expect(q.template, 'proposal');
      expect(q.title, 'Shop CRM');
      expect(q.clientId, 'c1');
      expect(q.projectId, 'p1');
      expect(q.taxPct, 18);
      expect(q.items.length, 4);
      expect(q.items[0].todoId, 't1', reason: 'a line made from a deliverable links to it');
      expect(q.items[1].desc, startsWith('Inventory\nStock list, Purchase orders'));
      expect(q.items[3].desc, 'Training day');
      expect(q.items[3].todoId, isNotNull, reason: 'a new item also becomes a project deliverable');
      expect(store.project('p1')!.todos.any((x) => x.id == q.items[3].todoId && x.text == 'Training day'), isTrue);
      expect(q.sections.map((x) => x.title), containsAll(['Overview', 'Scope of work', 'Deliverables and features', 'Timeline', 'Payment terms', 'Validity']));
      expect(q.schedule.map((m) => m.pct), [50, 50]);
      expect(q.due.difference(DateTime.now()).inDays, inInclusiveRange(29, 30));
      expect(find.byType(DocDetailPage), findsOneWidget);
      expect(find.byKey(const Key('doc-schedule')), findsOneWidget);
      expect(find.byKey(const Key('doc-section-Scope of work')), findsOneWidget);
      expect(store.quotedIn('t1'), [q.number]);
    });

    testWidgets('a template and its clauses are chosen up front; terms options change the wording', (t) async {
      _seed();
      await pumpScreen(t, const QuoteBuilderPage(clientId: 'c1'), size: tall);
      await _tap(t, 'template-quick');
      await t.enterText(find.byKey(const Key('quote-brief')), 'Logo for a bakery.');
      await t.tap(find.widgetWithText(ChoicePill, '3'));
      await t.tap(find.widgetWithText(ChoicePill, 'Revisions and changes'));
      await t.tap(find.widgetWithText(ChoicePill, '2% a month'));
      await t.pump();
      await t.tap(find.widgetWithText(ChoicePill, 'Net 30'));
      await t.pump();
      await t.tap(find.byKey(const Key('quote-new-item')));
      await settle(t);
      await t.enterText(find.byKey(const Key('line-desc')), 'Logo');
      await t.enterText(find.byKey(const Key('line-rate')), '9000');
      await t.tap(find.byKey(const Key('line-save')));
      await settle(t);
      await _tap(t, 'quote-create');
      final q = store.docs.single;
      expect(q.template, 'quick');
      final titles = q.sections.map((x) => x.title).toList();
      expect(titles, ['Overview', 'Scope of work', 'Payment terms', 'Revisions and changes', 'Validity'], reason: 'the item is the scope; quick quote clauses + the one switched on');
      expect(q.sections.firstWhere((x) => x.title == 'Payment terms').body, allOf(contains('Net 30'), contains('late charge of 2% per month')));
      expect(q.sections.firstWhere((x) => x.title == 'Revisions and changes').body, contains('Up to 3 rounds'));
    });

    testWidgets('without the AI model, Generate reads priced lines from the text', (t) async {
      _seed();
      await pumpScreen(t, const QuoteBuilderPage(clientId: 'c1'), size: tall);
      await t.enterText(find.byKey(const Key('quote-brief')), 'Poster 3x @ 1500\nBanner 2 @ 800');
      await _tap(t, 'quote-generate');
      expect(find.byKey(const Key('line-0')), findsOneWidget);
      expect(find.byKey(const Key('line-1')), findsOneWidget);
      expect(find.textContaining('₹1,500'), findsWidgets);
      await _tap(t, 'quote-create');
      expect(store.docs.single.items.map((i) => i.desc.toLowerCase()), containsAll([contains('poster'), contains('banner')]));
      expect(store.docs.single.items.first.todoId, isNull, reason: 'no project, nothing to link');
    });

    testWidgets('refuses to create without a client or without items', (t) async {
      _seed();
      await pumpScreen(t, const QuoteBuilderPage(), size: tall);
      await _tap(t, 'quote-create');
      expect(find.text('Choose a client'), findsWidgets);
      expect(store.docs, isEmpty);
      await t.tap(find.byType(DropdownButtonFormField<String>).first);
      await settle(t);
      await t.tap(find.text('Acme Corp').last);
      await settle(t);
      await _tap(t, 'quote-create');
      expect(store.docs, isEmpty, reason: 'no items yet');
      expect(find.textContaining('Add at least one item'), findsWidgets);
    });

    testWidgets('layouts fit a small phone with large text', (t) async {
      _seed();
      await pumpScreen(t, const QuoteBuilderPage(clientId: 'c1', projectId: 'p1'), size: const Size(320, 568), textScale: 1.5);
      await _scrollAll(t);
      expect(t.takeException(), isNull);
    });
  });

  group('Invoice builder', () {
    testWidgets('bills a quotation in full: copies it, links both ways, applies template, terms and late fee', (t) async {
      _seed();
      store.docs = [_quote()];
      await pumpScreen(t, const InvoiceBuilderPage(clientId: 'c1'), size: tall);
      expect(find.text('New invoice'), findsOneWidget);
      expect(find.textContaining('Copies every line'), findsOneWidget);
      await t.tap(find.byKey(const Key('template-modern')));
      await t.tap(find.text('Net 30').first);
      await t.tap(find.text('2% a month').first);
      await t.pump();
      await _tap(t, 'invoice-create');
      expect(t.takeException(), isNull);
      final inv = store.docs.firstWhere((d) => d.isInvoice);
      final q = store.doc('q1')!;
      expect(q.convertedToId, inv.id);
      expect(q.status, 'accepted');
      expect(inv.template, 'modern');
      expect(inv.terms, 'Net 30');
      expect(inv.due.difference(inv.date).inDays, 30);
      expect(inv.items.single.desc, 'Build');
      expect(inv.taxPct, 18);
      expect(inv.notes, contains('charge of 2% per month'));
      expect(find.byType(DocDetailPage), findsOneWidget);
    });

    testWidgets('bills one payment step of a quotation as a single line without converting it', (t) async {
      _seed();
      store.docs = [_quote()];
      await pumpScreen(t, const InvoiceBuilderPage(clientId: 'c1'), size: tall);
      await t.tap(find.textContaining('Advance, on approval'));
      await t.pump();
      expect(find.textContaining('Invoice total ₹5,900 '), findsOneWidget, reason: '50% of 10,000 + 18% tax');
      await _tap(t, 'invoice-create');
      final inv = store.docs.firstWhere((d) => d.isInvoice);
      expect(inv.items.single.rate, 5000);
      expect(inv.items.single.desc, contains('against QT-2026-001'));
      expect(inv.total, 5900);
      expect(store.doc('q1')!.convertedToId, isNull, reason: 'a part payment does not close the quotation');
    });

    testWidgets('refuses to bill a quotation in full twice', (t) async {
      _seed();
      final q = _quote();
      store.docs = [q];
      final done = store.quoteToInvoice(q);
      await pumpScreen(t, const InvoiceBuilderPage(clientId: 'c1'), size: tall);
      expect(find.textContaining('already invoiced as ${done.number}'), findsOneWidget);
      final before = store.docs.length;
      await _tap(t, 'invoice-create');
      expect(store.docs.length, before);
    });

    testWidgets('bills finished project work: the done deliverables are ticked and the invoice links to them', (t) async {
      _seed();
      await pumpScreen(t, const InvoiceBuilderPage(clientId: 'c1', projectId: 'p1'), size: tall);
      expect(find.byKey(const Key('invoice-from-deliverables')), findsOneWidget, reason: 'a project with deliverables starts on project work');
      await _tap(t, 'invoice-from-deliverables');
      expect(find.text('Bill 1 deliverable'), findsOneWidget, reason: 'only the finished one is pre-ticked');
      await t.tap(find.byKey(const Key('pick-confirm')));
      await settle(t);
      await _tap(t, 'invoice-create');
      final inv = store.docs.single;
      expect(inv.isInvoice, isTrue);
      expect(inv.projectId, 'p1');
      expect(inv.items.single.todoId, 't1');
      expect(inv.items.single.qty, 10);
      expect(inv.items.single.rate, 1000);
      expect(inv.taxPct, 18);
      expect(store.quotedIn('t1'), [inv.number]);
    });

    testWidgets('blank invoice: add an item by hand', (t) async {
      _seed();
      await pumpScreen(t, const InvoiceBuilderPage(clientId: 'c1'), size: tall);
      await t.tap(find.text('Blank'));
      await t.pump();
      await _tap(t, 'invoice-new-item');
      await t.enterText(find.byKey(const Key('line-desc')), 'Consulting');
      await t.enterText(find.byKey(const Key('line-qty')), '3');
      await t.enterText(find.byKey(const Key('line-unit')), 'hrs');
      await t.enterText(find.byKey(const Key('line-rate')), '2000');
      await t.tap(find.byKey(const Key('line-save')));
      await settle(t);
      await _tap(t, 'invoice-create');
      final inv = store.docs.single;
      expect(inv.items.single.desc, 'Consulting');
      expect(inv.items.single.unit, 'hrs');
      expect(inv.total, 7080, reason: '3 x 2,000 + 18% tax');
      expect(inv.template, 'classic');
    });

    testWidgets('layouts fit a small phone with large text', (t) async {
      _seed();
      store.docs = [_quote()];
      await pumpScreen(t, const InvoiceBuilderPage(clientId: 'c1'), size: const Size(320, 568), textScale: 1.5);
      await _scrollAll(t);
      expect(t.takeException(), isNull);
    });
  });

  group('Deliverables: bulk add and bulk remove', () {
    testWidgets('bulk add reads typed lines, hours and subtasks', (t) async {
      _seed();
      store.projects = [Project(id: 'p1', clientId: 'c1', name: 'CRM')];
      await pumpScreen(t, const ProjectDetailPage('p1'), size: tall);
      await _tap(t, 'bulk-add');
      expect(find.byKey(const Key('bulk-confirm')), findsOneWidget);
      await t.enterText(find.byKey(const Key('bulk-text')), 'Staff management | 40\n- Profiles | 16\n- Attendance | 14\nInventory | 30\nInvoicing');
      await t.pump();
      expect(find.text('3 deliverables, 2 subtasks, 60h'), findsOneWidget);
      await t.tap(find.byKey(const Key('bulk-confirm')));
      await settle(t);
      final todos = store.project('p1')!.todos;
      expect(todos.map((x) => x.text), ['Staff management', 'Inventory', 'Invoicing']);
      expect(todos.first.sub.map((x) => x.text), ['Profiles', 'Attendance']);
      expect(todos[1].hours, '30h');
      expect(find.text('Invoicing'), findsOneWidget);
    });

    testWidgets('select several deliverables and remove them together, after a confirmation', (t) async {
      _seed();
      await pumpScreen(t, const ProjectDetailPage('p1'), size: tall);
      await _tap(t, 'select-tasks');
      expect(find.text('0 selected'), findsOneWidget);
      expect(find.byKey(const Key('select-delete')), findsNothing);
      await t.tap(find.byKey(const Key('select-t1')));
      await t.tap(find.byKey(const Key('select-t3')));
      await t.pump();
      expect(find.text('2 selected'), findsOneWidget);
      await _tap(t, 'select-delete');
      expect(find.text('Delete 2 deliverables?'), findsOneWidget);
      await t.tap(find.text('Delete').last);
      await settle(t);
      expect(store.project('p1')!.todos.map((x) => x.id), ['t2']);
      expect(find.byKey(const Key('select-count')), findsNothing, reason: 'selection mode ends after deleting');
    });

    testWidgets('Select all, then Cancel leaves everything in place', (t) async {
      _seed();
      await pumpScreen(t, const ProjectDetailPage('p1'), size: tall);
      await _tap(t, 'select-tasks');
      await t.tap(find.byKey(const Key('select-all')));
      await t.pump();
      expect(find.text('3 selected'), findsOneWidget);
      await t.tap(find.byKey(const Key('select-cancel')));
      await settle(t);
      expect(store.project('p1')!.todos.length, 3);
      expect(find.byKey(const Key('add-task')), findsOneWidget);
    });

    testWidgets('a deliverable shows the quotations and invoices it appears on', (t) async {
      _seed();
      store.docs = [
        Doc(id: 'q1', kind: 'quote', number: 'QT-1', clientId: 'c1', items: [LineItem(desc: 'x', todoId: 't1')]),
        Doc(id: 'i1', kind: 'invoice', number: 'INV-1', clientId: 'c1', items: [LineItem(desc: 'x', todoId: 't1')]),
      ];
      await pumpScreen(t, const ProjectDetailPage('p1'), size: tall);
      expect(find.byKey(const Key('docs-t1')), findsOneWidget);
      expect(find.text('In QT-1, INV-1'), findsOneWidget);
      expect(find.byKey(const Key('docs-t2')), findsNothing);
    });
  });

  group('Document editor extras', () {
    testWidgets('edit a quotation\'s schedule and sections, switch template, add lines from deliverables', (t) async {
      _seed();
      final q = _quote()
        ..sections = [DocSection('Scope of work', '- Build the CRM')]
        ..template = 'standard';
      store.docs = [q];
      await pumpScreen(t, DocEditor(store.doc('q1')!), size: tall);
      expect(find.byKey(const Key('template-proposal')), findsOneWidget);
      await t.tap(find.byKey(const Key('template-proposal')));
      await t.enterText(find.byKey(const Key('section-title-0')), 'What we will build');
      await t.enterText(find.byKey(const Key('section-body-0')), '- CRM\n- Reports');
      await _tap(t, 'section-add');
      await t.enterText(find.byKey(const Key('section-title-1')), 'Notes');
      await t.enterText(find.byKey(const Key('section-body-1')), 'Hosting not included.');
      await _tap(t, 'schedule-add');
      await t.enterText(find.byKey(const Key('schedule-label-2')), 'After launch');
      await t.enterText(find.byKey(const Key('schedule-pct-2')), '10');
      await t.pump();
      expect(find.text('Adds up to 110%, should be 100%'), findsOneWidget);
      await t.enterText(find.byKey(const Key('schedule-pct-0')), '40');
      await t.pump();
      expect(find.text('Adds up to 100%'), findsOneWidget);

      await _tap(t, 'editor-from-deliverables');
      await t.tap(find.byKey(const Key('pick-t2')));
      await t.pump();
      await t.tap(find.byKey(const Key('pick-confirm')));
      await settle(t);

      await t.ensureVisible(find.text('Save changes'));
      await t.tap(find.text('Save changes'));
      await settle(t);
      final saved = store.doc('q1')!;
      expect(saved.template, 'proposal');
      expect(saved.sections.map((x) => x.title), ['What we will build', 'Notes']);
      expect(saved.sections.first.body, '- CRM\n- Reports');
      expect(saved.schedule.map((m) => (m.label, m.pct)), [('Advance, on approval', 40), ('On delivery', 50), ('After launch', 10)]);
      expect(saved.items.length, 2);
      expect(saved.items.last.todoId, 't2');
      expect(saved.items.last.qty, 20);
    });

    testWidgets('the editor and document page fit a small phone with large text for a detailed quotation', (t) async {
      _seed();
      final q = _quote()
        ..sections = [DocSection('Timeline', 'Phase | Work | Duration\n1 | Staff management | 2 weeks\nEstimated total: 2 weeks'), DocSection('Scope', '- one\n- two')];
      store.docs = [q];
      await pumpScreen(t, DocEditor(store.doc('q1')!), size: const Size(320, 568), textScale: 1.5);
      await _scrollAll(t);
      expect(t.takeException(), isNull);
      await pumpScreen(t, const DocDetailPage('q1'), size: const Size(320, 568), textScale: 1.5);
      await _scrollAll(t);
      expect(t.takeException(), isNull);
      await t.drag(find.byType(ListView).first, const Offset(0, 4000)); // back to the top
      await t.pump();
      for (var i = 0; i < 8 && find.byType(DocBlocksView).evaluate().isEmpty; i++) {
        await t.drag(find.byType(ListView).first, const Offset(0, -250));
        await t.pump();
      }
      expect(find.byType(DocBlocksView), findsWidgets);
    });
  });
}
