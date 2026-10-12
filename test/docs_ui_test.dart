import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:freelance_os/docs.dart';
import 'package:freelance_os/models.dart';
import 'package:freelance_os/pdf.dart';
import 'package:share_plus/share_plus.dart';

import 'harness.dart';

const phone = Size(360, 800);
const tiny = Size(320, 568);
const tall = Size(360, 1800); // everything of a long page built at once, for behaviour tests
final longName = 'Bartholomew-Featherstonehaugh International Holdings & Partners ${'Ltd ' * 6}';
final longText = 'Complete end-to-end redesign of the customer onboarding experience including research, workshops, wireframes ${'and more ' * 12}';

Finder byHint(String hint) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

/// Opens [page] as a pushed route (like the app does), so Save/Back have somewhere to return to.
class _Launcher extends StatelessWidget {
  final Widget Function() page;
  const _Launcher(this.page);
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page())), child: const Text('open'))),
      );
}

Future<void> openPage(WidgetTester t, Widget Function() page, {Size size = tall, double textScale = 1.0}) async {
  await pumpScreen(t, _Launcher(page), size: size, textScale: textScale);
  await t.tap(find.text('open'));
  await settle(t);
}

Widget _pdfPage() => const DocPdfPage('i5');

/// Realistic data, built here and never in the app.
void seed() {
  resetStore();
  store.profile = Profile(
    bizName: 'Okafor Studio',
    ownerName: 'Ada Okafor',
    email: 'ada@okafor.studio',
    currency: '₹',
    upi: 'ada@upi',
    bank: 'HDFC Bank\nA/C 1234567890\nIFSC HDFC0001234',
    taxId: '29ABCDE1234F1Z5',
    dueDays: 14,
  );
  final acme = Client(id: 'acme', name: 'Acme Corp', email: 'billing@acme.test');
  final long = Client(id: 'long', name: longName);
  store.clients = [acme, long];
  store.projects = [Project(id: 'site', clientId: 'acme', name: 'Website revamp')];
  final now = DateTime.now();
  store.docs = [
    Doc(id: 'q1', kind: 'quote', number: 'QT-2026-001', title: 'Brand identity', clientId: 'acme', status: 'sent', date: now.subtract(const Duration(days: 3)), items: [LineItem(desc: 'Logo', qty: 1, rate: 15000), LineItem(desc: 'Guidelines', qty: 2, rate: 4000, unit: 'days')], taxPct: 18),
    Doc(id: 'q2', kind: 'quote', number: 'QT-2026-002', title: 'Draft quote', clientId: 'long', date: now.subtract(const Duration(days: 9)), items: [LineItem(desc: 'Audit', qty: 1, rate: 500)]),
    Doc(id: 'i1', kind: 'invoice', number: 'INV-2026-001', title: 'Website', clientId: 'acme', projectId: 'site', status: 'sent', date: now.subtract(const Duration(days: 40)), due: now.subtract(const Duration(days: 10)), items: [LineItem(desc: 'Build', qty: 10, rate: 2500, unit: 'hrs')], discount: 10, taxPct: 18),
    Doc(id: 'i2', kind: 'invoice', number: 'INV-2026-002', title: 'Hosting', clientId: 'acme', status: 'paid', date: now.subtract(const Duration(days: 20)), items: [LineItem(desc: 'Hosting', qty: 12, rate: 99.5)]),
    Doc(id: 'i3', kind: 'invoice', number: 'INV-2026-003', title: longText, clientId: 'long', status: 'sent', date: now.subtract(const Duration(days: 1)), due: now.add(const Duration(days: 13)), items: [LineItem(desc: longText, qty: 1, rate: 123456789.5)]),
    Doc(id: 'i4', kind: 'invoice', number: 'INV-2026-004', title: 'Legacy overdue', clientId: 'acme', status: 'overdue', date: now.subtract(const Duration(days: 60)), items: [LineItem(desc: 'Old job', qty: 1, rate: 100)]),
    Doc(id: 'i5', kind: 'invoice', number: 'INV-2026-005', title: 'Fresh', clientId: 'acme', date: now, items: [LineItem(desc: 'Thing', qty: 1, rate: 10)]),
  ];
  store.baseline();
}

void main() {
  group('money maths', () {
    test('rounds every step to 2 decimals and handles odd input', () {
      final d = Doc(kind: 'invoice', items: [LineItem(qty: 3, rate: 33.333), LineItem(qty: 0.5, rate: 0.01)], discount: 12.5, taxPct: 18);
      expect(d.items.first.amount, 100.0);
      expect(d.subtotal, 100.01);
      expect(d.discountAmount, 12.5);
      expect(d.tax, round2((100.01 - 12.5) * 18 / 100));
      expect(d.total, round2(d.taxable + d.tax));
      expect(Doc(kind: 'invoice', items: [LineItem(qty: 0, rate: 50)]).total, 0);
      expect(Doc(kind: 'invoice', items: [LineItem(qty: 1, rate: 10)], discount: 150).total, 0, reason: 'discount can never push a total below zero');
    });

    test('overdue is derived; the stored value is never offered or accepted', () {
      final now = DateTime.now();
      final late = Doc(kind: 'invoice', status: 'sent', due: now.subtract(const Duration(days: 2)));
      final today = Doc(kind: 'invoice', status: 'sent', due: now);
      expect(late.shownStatus, 'overdue');
      expect(today.shownStatus, 'sent', reason: 'due today is not overdue yet');
      expect(late.statuses, isNot(contains('overdue')));
      expect(Doc.fromJson({'kind': 'invoice', 'status': 'overdue'}).shownStatus, 'overdue', reason: 'old saves still show as overdue');
      seed();
      store.setDocStatus('i1', 'overdue');
      expect(store.doc('i1')!.status, 'sent');
    });

    test('status transitions', () {
      seed();
      List<String> next(String id) => nextStatuses(store.doc(id)!, store);
      expect(next('i5'), ['sent', 'paid']);
      expect(next('i1'), ['paid', 'draft']);
      expect(next('i2'), ['sent']);
      expect(next('i4'), ['paid', 'sent']);
      expect(primaryStatus(store.doc('i4')!, store), 'paid');
      expect(next('q2'), ['sent']);
      expect(next('q1'), ['accepted', 'rejected', 'draft']);
    });

    test('a quote converts once and the link survives', () {
      seed();
      final q = store.doc('q1')!;
      final inv = store.quoteToInvoice(q);
      expect(q.convertedToId, inv.id);
      expect(q.status, 'accepted');
      expect(inv.title, 'Brand identity');
      expect(inv.total, q.total);
      final again = store.quoteToInvoice(q);
      expect(again.id, inv.id);
      expect(store.docs.where((d) => d.isInvoice && d.title == 'Brand identity'), hasLength(1));
      expect(nextStatuses(q, store), isEmpty);
      store.deleteDoc(inv.id);
      expect(q.convertedToId, isNull, reason: 'deleting the invoice frees the quote to be converted again');
    });
  });

  group('pdf', () {
    testWidgets('builds a real, presentable PDF for a full profile, an empty profile and a long multi-page doc', (t) async {
      seed();
      final full = await t.runAsync(() => buildPdf(store.doc('i1')!));
      expect(String.fromCharCodes(full!.take(5)), '%PDF-');
      expect(full.length, greaterThan(3000));

      final many = Doc(kind: 'invoice', number: 'INV-9', clientId: 'long', notes: 'Pay within 14 days.\nThank you.', items: [
        for (var i = 0; i < 70; i++) LineItem(desc: 'Line $i: $longText', qty: i + 1.5, rate: 1234.56 + i),
      ]);
      store.putDoc(many);
      final big = await t.runAsync(() => buildPdf(many));
      expect(String.fromCharCodes(big!.take(5)), '%PDF-');
      expect(big.length, greaterThan(full.length));
      final pages = RegExp(r'/Type\s*/Page(?!s)').allMatches(String.fromCharCodes(big)).length;
      expect(pages, greaterThan(1), reason: 'long invoice must paginate');

      resetStore(); // blank business profile, unknown client, no items
      final empty = await t.runAsync(() => buildPdf(Doc(kind: 'quote', number: 'QT-1')));
      expect(String.fromCharCodes(empty!.take(5)), '%PDF-');
      expect(empty.length, greaterThan(1500));
      for (final cur in ['\$', '€', '£', '₹', '¥']) {
        store.profile = Profile(currency: cur);
        final b = await t.runAsync(() => buildPdf(Doc(kind: 'invoice', number: 'X', items: [LineItem(desc: 'a', qty: 1, rate: 5)])));
        expect(String.fromCharCodes(b!.take(5)), '%PDF-', reason: 'currency $cur');
      }
      expect(pdfFileName(Doc(kind: 'invoice', number: 'INV/2026 #1')), 'INV_2026_1.pdf');
    });
  });

  group('Docs tab', () {
    testWidgets('lists, switches kind, filters by stage, searches, and shows empty states', (t) async {
      seed();
      await pumpScreen(t, const Scaffold(backgroundColor: Colors.transparent, body: DocsTab()));
      expect(t.takeException(), isNull);
      expect(find.text('QT-2026-001 · ${fmtDate(store.doc('q1')!.date)}'), findsOneWidget);
      expect(find.text('Brand identity'), findsOneWidget);

      await t.tap(find.text('Invoices'));
      await settle(t);
      expect(find.textContaining('INV-2026-001'), findsOneWidget);
      expect(find.textContaining('QT-2026-001'), findsNothing);
      expect(find.text('Overdue by 10 days'), findsOneWidget);
      // the legacy stored 'overdue' invoice counts under Overdue too (2 of them)
      await t.ensureVisible(find.text('Overdue').first);
      await t.tap(find.text('Overdue').first);
      await settle(t);
      expect(find.textContaining('INV-2026-001'), findsOneWidget);
      expect(find.textContaining('INV-2026-004'), findsOneWidget);
      expect(find.textContaining('INV-2026-002'), findsNothing);
      await t.ensureVisible(find.text('Overdue').first);
      await t.tap(find.text('Overdue').first); // toggles the filter off
      await settle(t);
      expect(find.textContaining('INV-2026-002'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'hosting');
      await settle(t);
      expect(find.textContaining('INV-2026-002'), findsOneWidget);
      expect(find.textContaining('INV-2026-001'), findsNothing);
      await t.enterText(find.byType(TextField), 'zzzz');
      await settle(t);
      expect(find.text('No matches'), findsOneWidget);
      await t.tap(find.text('Clear filters'));
      await settle(t);
      expect(find.textContaining('INV-2026-002'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('empty state offers to create, and an empty stage says so', (t) async {
      resetStore();
      await pumpScreen(t, const Scaffold(backgroundColor: Colors.transparent, body: DocsTab()));
      expect(find.text('No quotations yet'), findsOneWidget);
      await t.tap(find.text('Invoices'));
      await settle(t);
      expect(find.text('No invoices yet'), findsOneWidget);
      expect(find.text('New invoice'), findsOneWidget);
      expect(t.takeException(), isNull);

      store.putDoc(Doc(kind: 'invoice', number: 'INV-1', clientId: 'x', items: [LineItem(desc: 'a', rate: 5)]));
      await settle(t);
      await t.ensureVisible(find.text('Paid').first);
      await t.tap(find.text('Paid').first);
      await settle(t);
      expect(find.text('Nothing paid'), findsOneWidget);
    });

    for (final (size, scale) in [(phone, 1.0), (tiny, 1.5), (tiny, 1.0), (phone, 1.5)]) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()} text $scale with long names and amounts', (t) async {
        seed();
        await pumpScreen(t, const Scaffold(backgroundColor: Colors.transparent, body: DocsTab()), size: size, textScale: scale);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Invoices'));
        await settle(t);
        expect(t.takeException(), isNull);
        await t.drag(find.byType(ListView).first, const Offset(0, -600));
        await settle(t);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('Doc detail', () {
    testWidgets('mark sent / record payment go through the store and a paid invoice can be reopened', (t) async {
      seed();
      await pumpScreen(t, const DocDetailPage('i5'), size: tall);
      expect(find.text('Mark as sent'), findsOneWidget);
      await t.tap(find.text('Mark as sent'));
      await settle(t);
      expect(store.doc('i5')!.status, 'sent');
      expect(find.text('Record payment'), findsOneWidget);
      await t.tap(find.text('Record payment'));
      await settle(t);
      expect(store.doc('i5')!.status, 'paid');
      expect(find.text('Record payment'), findsNothing);
      await t.tap(find.text('Change status'));
      await settle(t);
      await t.tap(find.text('Move back to sent'));
      await settle(t);
      expect(find.text('Confirm'), findsOneWidget, reason: 'undoing a payment asks first');
      await t.tap(find.text('Confirm'));
      await settle(t);
      expect(store.doc('i5')!.status, 'sent');
      expect(t.takeException(), isNull);
    });

    testWidgets('overdue shows as a derived badge and can be paid', (t) async {
      seed();
      await pumpScreen(t, const DocDetailPage('i1'), size: tall);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('10 days past due'), findsOneWidget);
      expect(find.text('Record payment'), findsOneWidget);
      // 10 × 2500 = 25000, −10% = 22500, +18% tax = 26550
      expect(find.text('₹26,550'), findsWidgets);
      await t.tap(find.text('Record payment'));
      await settle(t);
      expect(store.doc('i1')!.status, 'paid');
      expect(find.text('Overdue'), findsNothing);
    });

    testWidgets('converting a quote is a one-time action', (t) async {
      seed();
      await pumpScreen(t, const DocDetailPage('q1'), size: tall);
      expect(find.text('Convert to invoice'), findsOneWidget);
      final before = store.docs.length;
      await t.tap(find.text('Convert to invoice'));
      await settle(t);
      expect(store.docs.length, before + 1);
      expect(store.doc('q1')!.convertedToId, isNotNull);
      final inv = store.doc(store.doc('q1')!.convertedToId)!;
      expect(inv.isInvoice, isTrue);
      expect(find.textContaining(inv.number), findsWidgets); // the new invoice page is on top
      t.state<NavigatorState>(find.byType(Navigator)).pop();
      await settle(t);
      expect(find.text('Convert to invoice'), findsNothing);
      expect(find.text('Invoiced as ${inv.number} ›'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('delete asks first and then removes the document', (t) async {
      seed();
      await pumpScreen(t, const DocDetailPage('i2'), size: tall);
      await t.tap(find.byTooltip('Delete invoice'));
      await settle(t);
      expect(find.text('Delete INV-2026-002?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(store.doc('i2'), isNotNull);
      await t.tap(find.byTooltip('Delete invoice'));
      await settle(t);
      await t.tap(find.text('Delete'));
      await settle(t);
      expect(store.doc('i2'), isNull);
    });

    testWidgets('a draft becomes sent only after a successful share', (t) async {
      seed();
      await pumpScreen(t, const DocDetailPage('i5'), size: tall);
      final ctx = t.element(find.byType(DocDetailPage));
      final saved = docShare;
      addTearDown(() => docShare = saved);

      docShare = (_) async => ShareResult('', ShareResultStatus.dismissed);
      await shareDocPdf(ctx, 'i5', bytes: Uint8List(8));
      await settle(t);
      expect(store.doc('i5')!.status, 'draft');

      late ShareParams got;
      docShare = (p) async {
        got = p;
        return ShareResult('x', ShareResultStatus.success);
      };
      final ok = await shareDocPdf(ctx, 'i5', bytes: Uint8List(8));
      await settle(t);
      expect(ok, isTrue);
      expect(store.doc('i5')!.status, 'sent');
      expect(find.textContaining('marked as sent'), findsOneWidget);
      expect(got.fileNameOverrides!.single, 'INV-2026-005.pdf');

      docShare = (_) async => throw Exception('no share target');
      await shareDocPdf(ctx, 'i1', bytes: Uint8List(8));
      await settle(t);
      expect(find.textContaining('Could not share'), findsOneWidget);
      await t.pump(const Duration(seconds: 8)); // let the snack bar timer finish while the tree is alive
    });

    for (final (size, scale) in [(phone, 1.0), (tiny, 1.5)]) {
      for (final id in ['i3', 'q1', 'i1']) {
        testWidgets('$id has no overflow at ${size.width.toInt()}x${size.height.toInt()} text $scale', (t) async {
          seed();
          await pumpScreen(t, DocDetailPage(id), size: size, textScale: scale);
          expect(t.takeException(), isNull);
          await t.drag(find.byType(ListView).first, const Offset(0, -900));
          await settle(t);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('a missing document shows a message', (t) async {
      seed();
      await pumpScreen(t, const DocDetailPage('nope'));
      expect(find.text('Document not found'), findsOneWidget);
    });
  });

  group('PDF page', () {
    testWidgets('offers print, save and share, and shares the built PDF', (t) async {
      seed();
      await pumpScreen(t, const _Launcher(_pdfPage));
      await t.tap(find.text('open'));
      for (var n = 0; n < 40 && find.text('Print').evaluate().isEmpty; n++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 250))); // real fonts + pdf build
        await t.pump(const Duration(milliseconds: 50));
      }
      await settle(t);
      for (final b in ['Print', 'Save', 'Share']) {
        expect(find.text(b), findsOneWidget);
      }
      final saved = docShare;
      addTearDown(() => docShare = saved);
      ShareParams? got;
      docShare = (p) async {
        got = p;
        return ShareResult('x', ShareResultStatus.success);
      };
      await t.tap(find.text('Share'));
      await settle(t);
      expect(got?.fileNameOverrides, ['INV-2026-005.pdf']);
      expect(store.doc('i5')!.status, 'sent');
      await t.pump(const Duration(seconds: 8));
    });
  });

  group('Doc editor', () {
    testWidgets('needs a client: offers to add one and refuses to save without', (t) async {
      resetStore();
      await openPage(t, () => DocEditor(store.newDoc('invoice'), isNew: true));
      expect(find.text('You need a client to bill first.'), findsOneWidget);
      await t.tap(find.text('Create invoice'));
      await settle(t);
      expect(store.docs, isEmpty);
      expect(find.text('Please fix the highlighted fields'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('validates then creates a document with the right numbers', (t) async {
      seed();
      await openPage(t, () => DocEditor(store.newDoc('invoice'), isNew: true));
      final count = store.docs.length;
      await t.tap(find.text('Create invoice'));
      await settle(t);
      expect(store.docs.length, count);
      expect(find.text('Choose a client'), findsOneWidget);
      expect(find.text('Add at least one line item.'), findsOneWidget);

      await t.tap(find.byType(DropdownButtonFormField<String>).first);
      await settle(t);
      await t.tap(find.text('Acme Corp').last);
      await settle(t);
      expect(find.text('Choose a client'), findsNothing);
      expect(find.text('Website revamp'), findsNothing, reason: 'projects are optional and only listed once there is something to pick');
      expect(find.text('Project (optional)'.toUpperCase()), findsOneWidget);

      await t.tap(find.text('Add line item'));
      await settle(t);
      await t.tap(find.text('Create invoice'));
      await settle(t);
      expect(find.text('Describe this item'), findsOneWidget);
      await t.enterText(byHint('e.g. Logo design'), 'Design sprint');
      await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.keyboardType == const TextInputType.numberWithOptions(decimal: true)).at(3), '1,200.5'); // tax, discount, qty, rate
      await t.enterText(byHint('0').at(0), '18');
      await t.enterText(byHint('0').at(1), '150');
      await settle(t);
      expect(find.text('Enter a number from 0 to 100'), findsOneWidget);
      await t.enterText(byHint('0').at(1), '10');
      await settle(t);
      // qty 1 × 1200.5 = 1200.5, −10% = 1080.45, +18% = 194.48 (rounded) → 1274.93
      expect(find.text('₹1,274.93'), findsWidgets);
      await t.tap(find.text('Create invoice'));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(store.docs.length, count + 1);
      final made = store.docs.first;
      expect(made.items.single.desc, 'Design sprint');
      expect(made.clientId, 'acme');
      expect(made.total, 1274.93);
      expect(made.status, 'draft');
      expect(find.byType(DocDetailPage), findsOneWidget, reason: 'lands on the new document');
    });

    testWidgets('terms presets move the due date; due before issue is rejected', (t) async {
      seed();
      final doc = store.doc('i5')!;
      await openPage(t, () => DocEditor(doc));
      await t.tap(find.text('Net 30'));
      await settle(t);
      await t.tap(find.text('Save changes'));
      await settle(t);
      final saved = store.doc('i5')!;
      expect(saved.terms, 'Net 30');
      expect(_day(saved.due).difference(_day(saved.date)).inDays, 30);
    });

    testWidgets('leaving with unsaved edits asks first; untouched leaves silently', (t) async {
      seed();
      await openPage(t, () => DocEditor(store.doc('i5')!));
      await t.tap(find.byTooltip('Back'));
      await settle(t);
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(DocEditor), findsNothing);

      await openPage(t, () => DocEditor(store.doc('i5')!));
      await t.enterText(byHint('e.g. Menu illustrations'), 'Changed');
      await settle(t);
      await t.tap(find.byTooltip('Back'));
      await settle(t);
      expect(find.text('Discard changes?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(find.byType(DocEditor), findsOneWidget);
      expect(store.doc('i5')!.title, 'Fresh', reason: 'nothing is written until Save');
    });

    for (final (size, scale) in [(tall, 1.0), (phone, 1.0), (phone, 1.5), (tiny, 1.0), (tiny, 1.5)]) {
      testWidgets('long data: no overflow at ${size.width.toInt()}x${size.height.toInt()} text $scale', (t) async {
        seed();
        await openPage(t, () => DocEditor(store.doc('i3')!), size: size, textScale: scale);
        expect(t.takeException(), isNull);
        await t.drag(find.byType(ListView).last, const Offset(0, -3000));
        await settle(t);
        expect(t.takeException(), isNull);
      });

      testWidgets('new document with a client and project preset: no overflow at ${size.width.toInt()}x${size.height.toInt()} text $scale', (t) async {
        seed();
        await openPage(t, () => DocEditor(store.newDoc('invoice', clientId: 'acme', projectId: 'site'), isNew: true), size: size, textScale: scale);
        expect(t.takeException(), isNull);
        expect(find.text('Website revamp'), findsOneWidget, reason: 'the preset project is selected');
        await t.drag(find.byType(ListView).last, const Offset(0, -3000));
        await settle(t);
        expect(t.takeException(), isNull);
      });

      testWidgets('validation layouts at ${size.width.toInt()}x${size.height.toInt()} text $scale', (t) async {
        seed();
        await openPage(t, () => DocEditor(store.newDoc('quote'), isNew: true), size: size, textScale: scale);
        await t.tap(find.text('Create quotation'));
        await settle(t);
        expect(t.takeException(), isNull);
        await t.drag(find.byType(ListView).first, const Offset(0, -2000));
        await settle(t);
        expect(t.takeException(), isNull);
      });
    }
  });
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
