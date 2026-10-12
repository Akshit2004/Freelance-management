import 'package:flutter/material.dart';
import 'package:freelance_os/docs.dart';
import 'package:freelance_os/home.dart';
import 'package:freelance_os/magic.dart';
import 'package:freelance_os/models.dart';
import 'package:freelance_os/projects.dart';
import 'package:freelance_os/settings.dart';
import 'package:freelance_os/state.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'harness.dart';

const small = Size(320, 568);
const normal = Size(360, 800);
const tall = Size(360, 1800); // everything built at once, so finders see the whole list
final longName = 'Extraordinarily Long Studio And Client Name Incorporated International ${'Holdings ' * 4}';

NavController navOf(WidgetTester t, Type page) => Provider.of<NavController>(t.element(find.byType(page)), listen: false);

/// A realistic store: one client, paid/sent/overdue invoices, a quote, projects with and without deadlines.
void seed({bool long = false}) {
  resetStore();
  final now = DateTime.now();
  store.profile = Profile(bizName: long ? longName : 'Lumen Works', ownerName: 'Ada', currency: '₹', defaultTax: 18);
  final c = Client(id: 'c-1', name: long ? longName : 'Northlight Cafe');
  store.clients = [c];
  Doc inv(String id, String status, double rate, DateTime date, {DateTime? due}) => Doc(
        id: id,
        kind: 'invoice',
        number: 'INV-$id',
        clientId: c.id,
        status: status,
        date: date,
        due: due,
        items: [LineItem(desc: 'Work', rate: rate)],
      );
  store.docs = [
    inv('1', 'paid', long ? 123456789.5 : 4000, DateTime(now.year, now.month, 1)),
    inv('2', 'paid', 2500, DateTime(now.year, now.month - 2, 15)),
    inv('3', 'paid', 900, DateTime(now.year, now.month - 9, 15)), // outside the six month window
    inv('4', 'sent', 1500, now, due: now.add(const Duration(days: 10))),
    inv('5', 'sent', 700, now.subtract(const Duration(days: 40)), due: now.subtract(const Duration(days: 3))), // overdue
    Doc(id: 'q', kind: 'quote', number: 'QT-1', clientId: c.id, status: 'sent', items: [LineItem(desc: 'Work', rate: 100)]),
  ];
  store.projects = [
    Project(id: 'far', clientId: c.id, name: long ? longName : 'Menu illustrations', deadline: now.add(const Duration(days: 30)), todos: [Todo(text: 'a'), Todo(text: 'b', done: true)]),
    Project(id: 'soon', clientId: c.id, name: 'Social kit', deadline: now.add(const Duration(days: 2)), todos: [Todo(text: 'a')]),
    Project(id: 'late', clientId: c.id, name: 'Logo refinements', deadline: now.subtract(const Duration(days: 2))),
    Project(id: 'none', clientId: c.id, name: 'No deadline project'),
    Project(id: 'fin', clientId: c.id, name: 'Finished project', status: 'done', deadline: now),
  ];
  store.baseline();
}

double dy(WidgetTester t, String text) => t.getTopLeft(find.text(text)).dy;

void main() {
  group('pure helpers', () {
    test('trailingMonths buckets paid invoices by invoice month and ignores the rest', () {
      final now = DateTime(2026, 10, 11);
      Doc d(String status, DateTime date, double rate, {String kind = 'invoice'}) => Doc(kind: kind, status: status, date: date, items: [LineItem(rate: rate)]);
      final m = trailingMonths([
        d('paid', DateTime(2026, 10, 1), 100),
        d('paid', DateTime(2026, 10, 30), 50),
        d('paid', DateTime(2026, 5, 31), 7),
        d('paid', DateTime(2026, 4, 30), 999), // too old
        d('sent', DateTime(2026, 10, 2), 999), // not paid
        d('paid', DateTime(2026, 9, 2), 999, kind: 'quote'),
      ], now);
      expect(m.map((e) => e.label), ['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct']);
      expect(m.map((e) => e.value), [7, 0, 0, 0, 0, 150]);
      // crossing a year boundary
      expect(trailingMonths([], DateTime(2026, 2, 1)).map((e) => e.label), ['Sep', 'Oct', 'Nov', 'Dec', 'Jan', 'Feb']);
    });

    test('dueLabel is relative for the near future and a date afterwards', () {
      final now = DateTime(2026, 10, 11, 23, 30);
      expect(dueLabel(DateTime(2026, 10, 11, 1), now), 'TODAY');
      expect(dueLabel(DateTime(2026, 10, 12), now), 'TOMORROW');
      expect(dueLabel(DateTime(2026, 10, 10), now), '1 DAY OVERDUE');
      expect(dueLabel(DateTime(2026, 10, 8), now), '3 DAYS OVERDUE');
      expect(dueLabel(DateTime(2026, 10, 16), now), 'IN 5 DAYS');
      expect(dueLabel(DateTime(2026, 12, 3), now), 'DEC 3');
    });
  });

  group('note parser', () {
    ParsedNotes parse(String s, {List<Client> clients = const [], String cur = '₹'}) => parseNotes(s, clients, cur);

    test('quantity, unit and rate in any currency', () {
      final p = parse('logo refinements 8h @ 85\nmenu illustrations 6x @ ₹120\nreels 3x @ 2k\nposters 2 @ \$1,20,000\nbanner 4 at Rs 1.5L');
      expect(p.items.map((i) => [i.desc, i.qty, i.unit, i.rate]), [
        ['logo refinements', 8, 'h', 85],
        ['menu illustrations', 6, 'x', 120],
        ['reels', 3, 'x', 2000],
        ['posters', 2, 'x', 120000],
        ['banner', 4, 'x', 150000],
      ]);
    });

    test('flat prices need a currency or k/L, or look like a price', () {
      final p = parse('social kit flat \$450\nwebsite €45k\nsticker pack £ 1,200\nlogo ¥30000\nbrochure 800\nrebrand phase 2\nin 2026');
      expect(p.items.map((i) => [i.desc, i.rate]), [
        ['social kit', 450],
        ['website', 45000],
        ['sticker pack', 1200],
        ['logo', 30000],
        ['brochure', 800],
      ]);
      expect(p.items.last.confidence < 80, isTrue); // bare number is flagged
      expect(p.unparsed, containsAll(['rebrand phase 2', 'in 2026']));
    });

    test('the profile currency symbol is understood too', () {
      final p = parse('logo CHF 450\nbanner 3x @ CHF 90', cur: 'CHF');
      expect(p.items.map((i) => [i.rate, i.qty]), [[450, 1], [90, 3]]);
    });

    test('tax, terms and discount can share one line and are not items', () {
      final p = parse('logo 2k\ntax 8%, net 14, 10% off');
      expect(p.items.length, 1);
      expect([p.tax, p.terms, p.discountPct], [8, 'Net 14', 10]);
      final q = parse('banner 5k\nno tax\ndue on receipt\ndiscount 500');
      expect([q.tax, q.terms, q.discountFlat], [0, 'Due on receipt', 500]);
    });

    test('known client is matched by name, unknown client becomes a candidate', () {
      final known = parse('northlight - rebrand phase 2\nlogo 8h @ 85', clients: [Client(id: 'n', name: 'Northlight Cafe')]);
      expect(known.clientId, 'n');
      expect(known.title, 'Rebrand phase 2');
      expect(known.items.length, 1);

      final unknown = parse('Zed Corp - website\nlogo 8h @ 85', clients: [Client(id: 'n', name: 'Northlight Cafe')]);
      expect(unknown.clientId, isNull);
      expect(unknown.clientCandidate, 'Zed Corp');
      expect(unknown.title, 'Website');

      final word = parse('banner and sign 2k', clients: [Client(id: 'a', name: 'An')]);
      expect(word.clientId, isNull); // "an" inside "and" must not match
    });
  });

  group('Home', () {
    testWidgets('first run shows the setup card and no invented data', (t) async {
      resetStore();
      await pumpScreen(t, const HomeTab(), size: tall);
      expect(t.takeException(), isNull);
      expect(find.text('Set up your studio'), findsOneWidget);
      expect(find.textContaining('Okafor'), findsNothing);
      expect(find.text('HEALTHY'), findsNothing);
      expect(find.text('ON TRACK'), findsNothing);
      expect(find.textContaining('last six months'), findsOneWidget); // empty chart, no fake bars
      expect(find.textContaining('No active projects yet'), findsOneWidget);
      expect(find.textContaining('Nothing yet'), findsOneWidget);

      await t.tap(find.text('Set up your studio'));
      await settle(t);
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('settings gear opens Settings', (t) async {
      seed();
      await pumpScreen(t, const HomeTab(), size: tall);
      await t.tap(find.bySemanticsLabel('Settings'));
      await settle(t);
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('chart, health and metrics come from the invoices', (t) async {
      seed();
      await pumpScreen(t, const HomeTab(), size: tall);
      expect(t.takeException(), isNull);
      expect(find.text('Set up your studio'), findsNothing);
      final now = DateTime.now();
      for (var k = 0; k < 6; k++) {
        expect(find.text(DateFormat('MMM').format(DateTime(now.year, now.month - k))), findsWidgets);
      }
      expect(find.text('OVERDUE'), findsOneWidget); // one invoice is past its due date
      expect(find.text('₹7,400'), findsOneWidget); // collected: every paid invoice (4000 + 2500 + 900)
      expect(find.textContaining('₹2,200 outstanding'), findsOneWidget);
      expect(find.text('1 overdue invoice'), findsOneWidget);
      expect(find.text('₹700'), findsOneWidget);
    });

    testWidgets('healthy books show ON TRACK, not OVERDUE', (t) async {
      seed();
      store.docs.removeWhere((d) => d.id == '5');
      await pumpScreen(t, const HomeTab(), size: tall);
      expect(find.text('ON TRACK'), findsOneWidget);
      expect(find.text('OVERDUE'), findsNothing);
    });

    testWidgets('due soon lists open projects with deadlines, nearest first, and opens the project', (t) async {
      seed();
      await pumpScreen(t, const HomeTab(), size: tall);
      expect(find.text('3 PROJECTS'), findsOneWidget);
      expect(find.text('No deadline project'), findsNothing);
      expect(find.text('Finished project'), findsNothing);
      expect(dy(t, 'Logo refinements') < dy(t, 'Social kit'), isTrue);
      expect(dy(t, 'Social kit') < dy(t, 'Menu illustrations'), isTrue);
      expect(find.text('2 DAYS OVERDUE'), findsOneWidget);
      expect(find.text('IN 2 DAYS'), findsOneWidget);
      expect(find.textContaining('1 task left'), findsNWidgets(2)); // "Social kit" and "Menu illustrations"

      await t.tap(find.text('Social kit'));
      await settle(t);
      expect(find.byType(ProjectDetailPage), findsOneWidget);
    });

    testWidgets('due soon says what is missing', (t) async {
      seed();
      store.projects.removeWhere((p) => p.deadline != null);
      await pumpScreen(t, const HomeTab(), size: tall);
      expect(find.textContaining('No deadlines set'), findsOneWidget);
    });

    testWidgets('metric cards jump to the right tab', (t) async {
      seed();
      await pumpScreen(t, const HomeTab(), size: tall);
      final nav = navOf(t, HomeTab);
      await t.tap(find.text('Active projects'));
      await settle(t);
      expect(nav.slot, NavController.projects);
      nav.go(NavController.home);
      await t.tap(find.text('Quotes pending'));
      await settle(t);
      expect(nav.slot, NavController.docs);
      nav.go(NavController.home);
      await t.tap(find.text('1 overdue invoice'));
      await settle(t);
      expect(nav.slot, NavController.docs);
    });

    testWidgets('counts are right', (t) async {
      seed();
      await pumpScreen(t, const HomeTab(), size: tall);
      // 3 active projects (far, soon, late, none are 'active' = 4), 1 quote pending
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('rebuilds when the store changes (Provider)', (t) async {
      seed();
      await pumpScreen(t, const HomeTab(), size: tall);
      expect(find.text('Social kit'), findsOneWidget);
      store.putProject(Project(id: 'new', clientId: 'c-1', name: 'Brand new thing', deadline: DateTime.now().add(const Duration(days: 1))));
      await settle(t);
      expect(find.text('Brand new thing'), findsOneWidget);
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.textContaining('Project "Brand new thing" started'), findsOneWidget); // activity feed too
    });

    testWidgets('activity feed copes with long text', (t) async {
      seed();
      store.activity = [Activity(text: 'Project "$longName" completed and a very long sentence follows it $longName', tone: 'good')];
      await pumpScreen(t, const HomeTab(), size: small, textScale: 1.5);
      expect(t.takeException(), isNull);
    });

    for (final (size, scale) in [(normal, 1.0), (small, 1.5), (small, 1.0), (normal, 1.5)]) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()} text $scale (realistic and very long data)', (t) async {
        seed();
        await pumpScreen(t, const HomeTab(), size: size, textScale: scale);
        expect(t.takeException(), isNull);
        seed(long: true);
        await pumpScreen(t, const HomeTab(), size: size, textScale: scale);
        expect(t.takeException(), isNull);
        resetStore();
        await pumpScreen(t, const HomeTab(), size: size, textScale: scale);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('Magic scratchpad', () {
    Future<void> type(WidgetTester t, String text) async {
      await t.enterText(find.byKey(const Key('magic-pad')), text);
      await settle(t);
    }

    testWidgets('starts empty with a hint, no dictate button, no sample data', (t) async {
      resetStore();
      await pumpScreen(t, const MagicPage());
      expect(t.takeException(), isNull);
      final field = t.widget<TextField>(find.byKey(const Key('magic-pad')));
      expect(field.controller!.text, isEmpty);
      expect(find.textContaining('Jot it down'), findsOneWidget);
      expect(find.textContaining('Dictate'), findsNothing);
      expect(find.textContaining('Northlight'), findsNothing);
      expect(find.textContaining('LIVE EXTRACTION · 0 LINES'), findsOneWidget);
      expect(find.textContaining('read here as you type'), findsOneWidget);
      expect(find.textContaining('no AI model installed'), findsOneWidget);
    });

    testWidgets('without a model the AI pill sends you to Settings', (t) async {
      resetStore();
      await pumpScreen(t, const MagicPage());
      await t.tap(find.text('Set up AI'));
      await settle(t);
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('extracts lines live in the profile currency', (t) async {
      resetStore();
      store.profile = Profile(currency: '€', defaultTax: 0, dueDays: 30);
      await pumpScreen(t, const MagicPage());
      await type(t, 'logo refinements 8h @ 85\nsocial kit flat \$450\nwe talked about maybe a sticker pack?\ntax 8%');
      expect(find.textContaining('LIVE EXTRACTION · 2 LINES'), findsOneWidget);
      expect(find.text('8 h × €85'), findsOneWidget);
      expect(find.text('€680'), findsOneWidget);
      expect(find.textContaining('Kept as notes'), findsOneWidget);
      expect(find.text('8%'), findsOneWidget);
      expect(find.text('Net 30'), findsNWidgets(2)); // the TERMS pill and the insert chip, both from the profile
      expect(t.takeException(), isNull);
    });

    testWidgets('helper chips insert syntax and the profile tax', (t) async {
      resetStore();
      store.profile = Profile(defaultTax: 12);
      await pumpScreen(t, const MagicPage());
      await t.tap(find.text('Tax 12%'));
      await settle(t);
      expect(t.widget<TextField>(find.byKey(const Key('magic-pad'))).controller!.text, 'tax 12%');
    });

    testWidgets('an empty pad explains instead of creating', (t) async {
      resetStore();
      await pumpScreen(t, const MagicPage());
      await t.tap(find.text('Invoice'));
      await settle(t);
      expect(find.textContaining('Nothing to build yet'), findsOneWidget);
      expect(store.docs, isEmpty);
    });

    testWidgets('unknown client: asks, then creates the client and the quotation', (t) async {
      resetStore();
      store.profile = Profile(defaultTax: 5);
      await pumpScreen(t, const MagicPage());
      await type(t, 'Zed Corp - website\nhome page design 3x @ 2k\nhosting flat 900\nnet 7, 10% off');
      expect(find.text('New · Zed Corp'), findsOneWidget);
      await t.tap(find.text('Quotation'));
      await settle(t);
      expect(find.textContaining('"Zed Corp" is not in your clients yet'), findsOneWidget);
      expect(store.docs, isEmpty);

      // empty name is refused
      await t.enterText(find.byType(TextField).last, '  ');
      await t.tap(find.text('Use new client'));
      await settle(t);
      expect(find.text('Type the client name'), findsOneWidget);

      await t.enterText(find.byType(TextField).last, 'Zed Corp');
      await t.tap(find.text('Use new client'));
      await settle(t);
      expect(store.clients.map((c) => c.name), ['Zed Corp']);
      expect(store.docs.length, 1);
      final d = store.docs.single;
      expect(d.kind, 'quote');
      expect(d.clientId, store.clients.single.id);
      expect(d.title, 'Website');
      expect(d.items.map((i) => [i.desc, i.qty, i.rate]), [['home page design', 3, 2000], ['hosting', 1, 900]]);
      expect([d.taxPct, d.discount, d.terms], [5, 10, 'Net 7']);
      expect(d.due.difference(d.date).inDays, 7);
      expect(find.byType(DocDetailPage), findsOneWidget);
    });

    testWidgets('known client is used without asking and the invoice is attached to its project', (t) async {
      seed();
      store.projects = [Project(id: 'p', clientId: 'c-1', name: 'Rebrand')];
      final before = store.docs.length;
      await pumpScreen(t, const MagicPage());
      await type(t, 'northlight - rebrand phase\nlogo 8h @ 85');
      expect(find.text('Northlight Cafe'), findsOneWidget);
      await t.tap(find.text('Invoice'));
      await settle(t);
      expect(find.text('Client'), findsNothing);
      expect(store.docs.length, before + 1);
      final d = store.docs.first;
      expect(d.isInvoice, isTrue);
      expect(d.clientId, 'c-1');
      expect(d.projectId, 'p');
      expect(d.items.single.rate, 85);
    });

    testWidgets('no clients at all: picking is required, cancel creates nothing', (t) async {
      resetStore();
      await pumpScreen(t, const MagicPage());
      await type(t, 'logo 8h @ 85');
      await t.tap(find.text('Invoice'));
      await settle(t);
      expect(find.textContaining('Who is this for?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(store.docs, isEmpty);
      expect(store.clients, isEmpty);
      expect(store.projects, isEmpty);
    });

    testWidgets('task board becomes a real project with todos and hours', (t) async {
      seed();
      store.projects = [];
      await pumpScreen(t, const MagicPage());
      await type(t, 'northlight - launch\nlogo 8h @ 85\nflyers 3x @ 200');
      await t.tap(find.text('Task board'));
      await settle(t);
      final p = store.projects.single;
      expect(p.name, 'Launch');
      expect(p.clientId, 'c-1');
      expect(p.budget, 8 * 85 + 600);
      expect(p.todos.map((x) => [x.text, x.hours]), [['logo', '8h'], ['flyers', '']]);
      expect(p.next, isEmpty);
      expect(find.byType(ProjectDetailPage), findsOneWidget);
    });

    testWidgets('tapping a line edits it with validation, remove and restore work', (t) async {
      seed();
      await pumpScreen(t, const MagicPage());
      await type(t, 'northlight\nlogo 8h @ 85\nbanner 2k');
      await t.tap(find.text('logo'));
      await settle(t);
      expect(find.text('CONFIDENCE INSPECTOR'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, '8'), '0');
      await settle(t);
      expect(find.text('Enter a number above 0'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, '0'), '10');
      await settle(t);
      await t.tap(find.text('Done'));
      await settle(t);
      expect(find.text('10 h × ₹85'), findsOneWidget);

      await t.tap(find.text('banner'));
      await settle(t);
      await t.tap(find.text('Remove this line'));
      await settle(t);
      expect(find.textContaining('LIVE EXTRACTION · 1 LINE'), findsOneWidget);
      await t.tap(find.textContaining('Restore'));
      await settle(t);
      expect(find.textContaining('LIVE EXTRACTION · 2 LINES'), findsOneWidget);
    });

    testWidgets('line editor fits a small screen with the keyboard up', (t) async {
      resetStore();
      await pumpScreen(t, const MagicPage(), size: small, textScale: 1.5);
      await type(t, 'a very long description of some deliverable that goes on and on 3x @ 2k');
      await t.ensureVisible(find.textContaining('3 ×'));
      await settle(t);
      await t.tap(find.textContaining('3 ×'));
      await settle(t);
      t.view.viewInsets = FakeViewPadding(bottom: 280 * 3);
      addTearDown(t.view.resetViewInsets);
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('Remove this line'), findsOneWidget);
    });

    testWidgets('closing with notes asks first', (t) async {
      resetStore();
      await pumpScreen(t, const MagicPage());
      await type(t, 'logo 8h @ 85');
      await t.tap(find.text('Close'));
      await settle(t);
      expect(find.text('Discard these notes?'), findsOneWidget);
    });

    testWidgets('keyboard open: extraction collapses to a one line summary and nothing overflows', (t) async {
      resetStore();
      await pumpScreen(t, const MagicPage(), size: small, textScale: 1.5);
      t.view.viewInsets = FakeViewPadding(bottom: 280 * 3);
      addTearDown(t.view.resetViewInsets);
      await type(t, 'logo 8h @ 85\nbanner 2k');
      expect(t.takeException(), isNull);
      expect(find.textContaining('LIVE EXTRACTION'), findsNothing);
      expect(find.textContaining('2 LINES'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('magic-pad'))).height, greaterThan(60));
    });

    for (final (size, scale) in [(normal, 1.0), (small, 1.5), (small, 1.0), (normal, 1.5)]) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()} text $scale with long notes', (t) async {
        seed(long: true);
        await pumpScreen(t, const MagicPage(), size: size, textScale: scale);
        expect(t.takeException(), isNull);
        await type(t, '$longName - ${'very long project title ' * 4}\n${'logo refinements ' * 6} 8h @ 85\n${'poster ' * 12} 12,34,56,789.50\ntax 18%, net 45, 15% off\n${'a note without a price ' * 8}');
        expect(t.takeException(), isNull);
        await t.tap(find.text('Task board'));
        await settle(t);
        expect(t.takeException(), isNull);
      });
    }
  });
}
