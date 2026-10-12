import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freelance_os/intro.dart';
import 'package:freelance_os/magic.dart';
import 'package:freelance_os/main.dart';
import 'package:freelance_os/models.dart';
import 'package:freelance_os/motion.dart';
import 'package:freelance_os/state.dart';
import 'package:freelance_os/ui.dart';
import 'package:provider/provider.dart';

import 'harness.dart';

const small = Size(320, 568), normal = Size(360, 800);
final longName = 'Extraordinarily Long Client And Business Name ' * 3;

/// Realistic data, built here and never in the app.
void populate() {
  final c = Client(name: longName, email: 'billing@example.com', phone: '+91 98765 43210');
  final c2 = Client(name: 'Zed');
  store
    ..putClient(c)
    ..putClient(c2)
    ..putProject(Project(
        clientId: c.id,
        name: 'Brand identity refresh for a very long named project',
        budget: 123456789.5,
        spent: 5000,
        deadline: DateTime.now().add(const Duration(days: 9)),
        todos: [Todo(text: 'Logo'), Todo(text: 'Palette', done: true)]))
    ..putProject(Project(clientId: c2.id, name: 'Site', status: 'review'))
    ..putDoc(Doc(kind: 'invoice', number: 'INV-1', clientId: c.id, status: 'sent', items: [LineItem(desc: 'Design', qty: 3, rate: 123456.5)]))
    ..putDoc(Doc(kind: 'quote', number: 'QUO-1', clientId: c2.id, items: [LineItem(desc: 'Build', rate: 900)]))
    ..putDoc(Doc(kind: 'invoice', number: 'INV-2', clientId: c2.id, status: 'overdue', due: DateTime.now().subtract(const Duration(days: 20)), items: [LineItem(desc: 'Fix', rate: 50)]));
}

Finder inBar(String text) => find.descendant(of: find.byType(HustlerNavBar), matching: find.text(text));
NavController navOf(WidgetTester t) => t.element(find.byType(HustlerNavBar)).read<NavController>();

void main() {
  setUp(resetStore);

  group('Shell', () {
    for (final size in [normal, small]) {
      for (final scale in [1.0, 1.5]) {
        for (final filled in [false, true]) {
          testWidgets('tabs + Magic at ${size.width.toInt()}x${size.height.toInt()} text $scale ${filled ? 'with data' : 'empty'}', (t) async {
            if (filled) populate();
            await pumpScreen(t, const Shell(), size: size, textScale: scale);
            expect(t.takeException(), isNull);
            for (final (slot, label) in [(1, 'Projects'), (2, 'Docs'), (3, 'Clients'), (0, 'Home')]) {
              await t.tap(inBar(label));
              await settle(t);
              expect(navOf(t).slot, slot, reason: label);
              expect(t.takeException(), isNull, reason: label);
            }
            await t.tap(inBar('Magic'));
            await settle(t);
            expect(find.byType(MagicPage), findsOneWidget);
            expect(t.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('hit targets: left / right / bottom edges and the raised top of the Magic button', (t) async {
      await pumpScreen(t, const Shell());
      final w = normal.width, h = normal.height;
      await t.tapAt(Offset(w - 2, h - 3)); // far right edge, bottom: Clients
      await settle(t);
      expect(navOf(t).slot, NavController.clients);
      await t.tapAt(Offset(2, h - 3)); // far left edge, bottom: Home
      await settle(t);
      expect(navOf(t).slot, NavController.home);
      await t.tapAt(Offset(w * .3, h - 40)); // Projects column
      await settle(t);
      expect(navOf(t).slot, NavController.projects);
      await t.tapAt(Offset(w / 2, h - 106 + 6)); // the highest few px of the raised circle
      await settle(t);
      expect(find.byType(MagicPage), findsOneWidget);
    });

    testWidgets('a double tap on Magic opens one page, not two', (t) async {
      await pumpScreen(t, const Shell());
      await t.tap(inBar('Magic'));
      await t.pump(const Duration(milliseconds: 30));
      await t.tapAt(Offset(normal.width / 2, normal.height - 106 + 10)); // second tap while the page is still animating in
      await settle(t);
      expect(find.byType(MagicPage), findsOneWidget);
    });

    testWidgets('tab content stops above the bar (gesture inset included)', (t) async {
      t.view.padding = const FakeViewPadding(bottom: 48 * 3, top: 24 * 3);
      addTearDown(t.view.resetPadding);
      populate();
      await pumpScreen(t, const Shell());
      final list = t.getRect(find.byType(RefreshListView));
      final bar = t.getRect(find.byType(HustlerNavBar));
      expect(bar.height, 80 + 26 + 48);
      expect(list.bottom, closeTo(bar.bottom - 80 - 48, .5)); // list ends exactly where the bar's body starts
      expect(t.takeException(), isNull);
    });

    testWidgets('toast floats above the bar and the Magic button', (t) async {
      await pumpScreen(t, const Shell());
      toast(t.element(find.byType(HustlerNavBar)), 'Saved');
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Saved'), findsOneWidget);
      expect(t.getRect(find.byType(SnackBar)).bottom, lessThanOrEqualTo(t.getRect(find.byType(HustlerNavBar)).top + .5));
    });

    testWidgets('back goes to Home first, tabs are selected in semantics', (t) async {
      final h = t.ensureSemantics();
      await pumpScreen(t, const Shell());
      await t.tap(inBar('Docs'));
      await settle(t);
      expect(t.getSemantics(find.bySemanticsLabel('Docs')), isSemantics(isSelected: true, isButton: true));
      expect(t.getSemantics(find.bySemanticsLabel('Home')), isSemantics(isSelected: false, isButton: true));
      await t.binding.handlePopRoute();
      await settle(t);
      expect(navOf(t).slot, NavController.home);
      h.dispose();
    });

    testWidgets('tab transition slides the way you travel', (t) async {
      await pumpScreen(t, const Shell());
      final nav = navOf(t);
      nav.go(NavController.clients);
      expect(nav.from, NavController.home);
      nav.go(NavController.projects);
      expect(nav.from, NavController.clients); // travelling back: dir = -1 in Shell
      nav.go(99); // unknown tab ids are ignored
      expect(nav.slot, NavController.projects);
      await settle(t);
      expect(t.takeException(), isNull);
    });

    testWidgets('reduced motion: no endless pulse in the bar', (t) async {
      await pumpScreen(t, Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: const Shell())));
      expect(t.takeException(), isNull);
      await t.tap(inBar('Clients'));
      await t.pump();
      expect(navOf(t).slot, NavController.clients);
    });
  });

  group('shared widgets', () {
    for (final size in [normal, small]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('Header / Section / pills / charts at ${size.width.toInt()} text $scale', (t) async {
          var added = 0;
          String seg = 'a';
          await pumpScreen(
            t,
            StatefulBuilder(
              builder: (c, set) => Scaffold(
                body: ListView(padding: const EdgeInsets.all(20), children: [
                  Header('Extraordinarily long header title that must wrap', sub: 'A long subtitle ' * 6, onAdd: () => added++),
                  Header('Projects', onAdd: () => added++),
                  Header('Supercalifragilisticexpialidocious_unbreakable_word', onAdd: () => added++),
                  Header('مرحبا بالعالم'),
                  Section('A very long section title that goes on and on and on', trailing: const Text('See all')),
                  Wrap(spacing: 6, children: [StatusPill('Overdue and then some long status text'), const StatusPill(''), const StatusPill('paid', uppercase: true)]),
                  CardContainer(onTap: () => added++, child: Text(longName)),
                  PillSegmentedControl<String>(
                    items: const ['a', 'b', 'c'],
                    selected: seg,
                    label: (s) => {'a': 'Quotations and estimates', 'b': 'Invoices and bills', 'c': 'Archived'}[s]!,
                    count: (s) => 12345,
                    onSelected: (s) => set(() => seg = s),
                  ),
                  const SizedBox(height: 12),
                  const DualProgressBar(donePct: .4, budgetPct: 1.4),
                  const DualProgressBar(donePct: double.nan, budgetPct: double.infinity, stacked: true),
                  const SizedBox(height: 12),
                  const CashflowBarChart(values: [0, 1200, double.nan, 99999999, 5, 340], labels: ['Jan', 'Feb', 'Mar', 'Apr']),
                  Row(children: [AvatarSquircle(longName), const AvatarSquircle('😀 emoji'), const AvatarSquircle('')]),
                  const EmptyState(Icons.inbox_outlined, 'Nothing here yet', 'Add your first item to see it listed here'),
                ]),
              ),
            ),
            size: size,
            textScale: scale,
          );
          expect(t.takeException(), isNull);
          await t.tap(find.byIcon(Icons.add_rounded).first);
          expect(added, 1);
          await t.scrollUntilVisible(find.textContaining('Invoices and bills'), 200);
          await t.tap(find.textContaining('Invoices and bills'));
          await settle(t);
          expect(seg, 'b');
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('Field follows data that changes behind it, but never while typing', (t) async {
      var value = 'Acme';
      String? typed;
      late void Function(void Function()) rebuild;
      await pumpScreen(
        t,
        Scaffold(
          body: StatefulBuilder(builder: (c, set) {
            rebuild = set;
            return Field('Name', value, (v) => typed = v);
          }),
        ),
      );
      expect(find.widgetWithText(TextFormField, 'Acme'), findsOneWidget);
      rebuild(() => value = 'Restored from backup'); // e.g. after a restore / refresh
      await t.pump();
      expect(find.widgetWithText(TextFormField, 'Restored from backup'), findsOneWidget);

      await t.tap(find.byType(TextFormField));
      await t.enterText(find.byType(TextFormField), '1.');
      expect(typed, '1.');
      rebuild(() => value = '1'); // parse round trip "1." -> 1 while the user is typing must not eat the dot
      await t.pump();
      expect(find.widgetWithText(TextFormField, '1.'), findsOneWidget);
    });

    testWidgets('Field passes validator / error / formatters / action through', (t) async {
      String? last;
      final key = GlobalKey<FormState>();
      await pumpScreen(
        t,
        Scaffold(
          body: Form(
            key: key,
            child: Column(children: [
              Field('Amount', '', (v) => last = v, keyboard: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], validator: (v) => (v ?? '').isEmpty ? 'Enter an amount' : null, textInputAction: TextInputAction.done),
              Field('Email', '', (_) {}, errorText: 'That email looks wrong', textCapitalization: TextCapitalization.none),
            ]),
          ),
        ),
        size: small,
        textScale: 1.5,
      );
      expect(find.text('That email looks wrong'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).first, 'a1b2');
      expect(last, '12');
      await t.enterText(find.byType(TextFormField).first, '');
      await t.pump();
      expect(find.text('Enter an amount'), findsOneWidget);
      expect(key.currentState!.validate(), isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets('Pressable grows a small child to a 44px touch target', (t) async {
      var taps = 0;
      await pumpScreen(t, Scaffold(body: Center(child: Pressable(onTap: () => taps++, semanticLabel: 'Tiny', child: const SizedBox(width: 20, height: 20)))));
      final c = t.getCenter(find.byType(SizedBox).last);
      await t.tapAt(c + const Offset(20, 0)); // 10px outside the visual child, inside 44
      expect(taps, 1);
      await t.tapAt(c + const Offset(0, -21));
      expect(taps, 2);
      await t.tapAt(c + const Offset(30, 0)); // outside 44
      expect(taps, 2);
      expect(t.getSize(find.byType(SizedBox).last), const Size(20, 20)); // layout untouched
    });

    testWidgets('Pressable is a button in semantics and skips the spring on reduced motion', (t) async {
      final h = t.ensureSemantics();
      await pumpScreen(
        t,
        Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: Scaffold(body: Center(child: Pressable(onTap: () {}, semanticLabel: 'Go', child: const Text('x')))))),
      );
      expect(t.getSemantics(find.bySemanticsLabel(RegExp('Go'))), isSemantics(isButton: true, hasTapAction: true));
      final g = await t.startGesture(t.getCenter(find.text('x')));
      await t.pump(const Duration(milliseconds: 150));
      expect(t.widget<Transform>(find.descendant(of: find.byType(Pressable), matching: find.byType(Transform)).first).transform.storage[0], closeTo(.97, .001));
      await g.up();
      h.dispose();
    });

    testWidgets('SplitText: reduced motion, RTL, long strings and unbreakable words render without errors', (t) async {
      await pumpScreen(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SplitText('Hello there', style: display(30)),
              SplitText('x' * 80, style: display(30)),
              SplitText('مرحبا', style: display(30)),
              SplitText('Unbreakable${'W' * 40}', style: display(30)),
              Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: SplitText('Reduced', style: display(30)))),
              Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: CountUp(1234, format: (v) => 'N${v.round()}'))),
            ]),
          ),
        ),
        size: small,
        textScale: 1.5,
      );
      expect(t.takeException(), isNull);
      expect(find.text('Reduced'), findsOneWidget); // plain Text, not split into letters
      expect(find.text('N1234'), findsOneWidget); // no roll-up
    });

    testWidgets('Screen: back button, long title, bottom area above the keyboard', (t) async {
      t.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(t.view.resetViewInsets);
      var saved = 0;
      await pumpScreen(
        t,
        Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => Navigator.push(c, zoom(Screen(title: 'A really long screen title that cannot fit on one line', body: Column(children: [Field('Name', 'x', (_) {})]), bottom: Pressable(onTap: () => saved++, child: const Text('Save'))))), child: const Text('open'))))),
        size: small,
        textScale: 1.5,
      );
      await t.tap(find.text('open'));
      await settle(t);
      expect(find.byType(Screen), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Save'));
      expect(saved, 1);
      await t.tap(find.byTooltip('Back'));
      await settle(t);
      expect(find.byType(Screen), findsNothing);
    });

    testWidgets('confirm: destructive verb is red, plain verb is not; dialog scrolls at 1.5x on a small phone', (t) async {
      bool? r1, r2;
      await pumpScreen(
        t,
        Builder(builder: (c) => Scaffold(body: Column(children: [
              TextButton(onPressed: () async => r1 = await confirm(c, 'Delete everything?', 'This cannot be undone. ' * 20), child: const Text('del')),
              TextButton(onPressed: () async => r2 = await confirm(c, 'Add a client first', 'Add one now?', verb: 'Add client'), child: const Text('add')),
            ]))),
        size: small,
        textScale: 1.5,
      );
      await t.tap(find.text('del'));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(t.widget<Text>(find.text('Delete')).style!.color, C.red);
      await t.tap(find.text('Delete'));
      await settle(t);
      expect(r1, isTrue);
      await t.tap(find.text('add'));
      await settle(t);
      expect(t.widget<Text>(find.text('Add client')).style!.color, C.text);
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(r2, isFalse);
    });

    testWidgets('pickDate survives out-of-range dates; numText / parseNum round trip', (t) async {
      await pumpScreen(t, Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => pickDate(c, DateTime(1900)), child: const Text('pick')))));
      await t.tap(find.text('pick'));
      await settle(t);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(t.takeException(), isNull);
      expect(numText(0.1 + 0.2), '0.3');
      expect(numText(12), '12');
      expect(numText(0), '');
      expect(numText(double.nan), '');
      expect(parseNum('1,234.5'), 1234.5);
    });
  });

  group('motion', () {
    testWidgets('RefreshListView: short list pulls to refresh and never gets stuck', (t) async {
      await pumpScreen(t, Scaffold(body: RefreshListView(padding: const EdgeInsets.all(20), children: const [Text('only item')])));
      double y() => t.getTopLeft(find.text('only item')).dy;
      final y0 = y();
      await t.fling(find.text('only item'), const Offset(0, 400), 1000);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(y(), closeTo(y0 + 56, 1)); // content makes room for the spinner while reloading
      // in tests the disk / path_provider never answers: the 8s guard must still release the spinner
      await settle(t, const Duration(seconds: 10));
      await t.pump(const Duration(seconds: 1));
      expect(y(), closeTo(y0, 1));
      expect(find.text('only item'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('RefreshListView disposed mid-refresh does not throw', (t) async {
      await pumpScreen(t, Scaffold(body: RefreshListView(children: const [Text('x')])));
      await t.fling(find.text('x'), const Offset(0, 400), 1000);
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      expect(t.takeException(), isNull);
    });

    testWidgets('Backdrop ticks, stops on reduced motion and disposes cleanly', (t) async {
      await pumpScreen(t, const Stack(children: [Positioned.fill(child: Backdrop())]));
      await t.pump(const Duration(seconds: 1));
      await pumpScreen(t, Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: const Backdrop())));
      await t.pump(const Duration(seconds: 1));
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
  });

  group('IntroOverlay', () {
    testWidgets('runs its timeline and calls onDone exactly once', (t) async {
      var done = 0;
      await pumpScreen(t, IntroOverlay(onDone: () => done++), size: small, textScale: 1.5);
      expect(done, 0);
      await t.pump(const Duration(seconds: 4));
      expect(done, 1);
      await t.pump(const Duration(seconds: 2));
      expect(done, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('tapping skips ahead and still calls onDone once (and lets taps through afterwards)', (t) async {
      var done = 0, behind = 0;
      await pumpScreen(
        t,
        Stack(children: [
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => behind++)),
          IntroOverlay(onDone: () => done++),
        ]),
        size: normal,
      );
      await t.tapAt(const Offset(180, 400));
      await t.pump(const Duration(milliseconds: 100));
      expect(behind, 0); // the overlay swallowed the skip tap
      await t.pump(const Duration(seconds: 1));
      expect(done, 1);
      await t.pump(const Duration(seconds: 3));
      expect(done, 1);
      await t.tapAt(const Offset(180, 400));
      expect(behind, 1); // overlay is IgnorePointer after done
    });

    testWidgets('reduced motion finishes quickly', (t) async {
      var done = 0;
      await pumpScreen(t, Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: IntroOverlay(onDone: () => done++))), size: small);
      await t.pump(const Duration(seconds: 1));
      expect(done, 1);
    });
  });

  group('theme', () {
    test('cursor, selection and snackbar are on brand', () {
      final th = hustlerTheme();
      expect(th.textSelectionTheme.cursorColor, C.orange);
      expect(th.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(th.datePickerTheme.headerBackgroundColor, C.dark);
    });
  });
}
