import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freelance_os/clients.dart';
import 'package:freelance_os/downloads.dart';
import 'package:freelance_os/main.dart' show hustlerTheme;
import 'package:freelance_os/models.dart';
import 'package:freelance_os/settings.dart';
import 'package:freelance_os/state.dart';
import 'package:provider/provider.dart';

import 'harness.dart';

const _small = Size(320, 568);
const _long = 'Extraordinarily Long Client Name Incorporated Holdings International Worldwide Partners (Pty) Ltd';

Doc _inv(String id, String clientId, String status, double rate, {DateTime? due}) => Doc(
      id: id,
      kind: 'invoice',
      number: 'INV-2026-$id',
      title: 'Work $id',
      clientId: clientId,
      status: status,
      due: due,
      items: [LineItem(desc: 'Work', qty: 1, rate: rate)],
    );

/// Pumps a launcher whose button pushes [screen], so Navigator.pop inside the screen works like in the app.
Future<void> _open(WidgetTester t, Widget screen, {Size size = const Size(360, 800), double textScale = 1.0}) async {
  await pumpScreen(
    t,
    Builder(
      builder: (context) => Scaffold(
        body: Center(child: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)), child: const Text('open'))),
      ),
    ),
    size: size,
    textScale: textScale,
  );
  await t.tap(find.text('open'));
  await settle(t);
}

Future<void> _scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 200);
  await t.pump();
}

/// Jumps the page to the bottom (a drag can land on a multi-line text field, which swallows it when the strings are very long).
Future<void> _jumpToEnd(WidgetTester t) async {
  final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
  pos.jumpTo(pos.maxScrollExtent);
  await settle(t);
  pos.jumpTo(pos.maxScrollExtent);
  await settle(t);
}

class _FakeDl extends ModelDownloads {
  final states = <String, DlInfo>{};
  @override
  DlInfo info(AiModel m) => states[m.id] ?? const DlInfo(Dl.none);
}

Future<void> _pumpWith(WidgetTester t, ModelDownloads dl, Widget screen, {Size size = const Size(360, 800), double textScale = 1.0}) async {
  await loadAppFonts();
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<Store>.value(value: store),
      ChangeNotifierProvider<ModelDownloads>.value(value: dl),
      ChangeNotifierProvider(create: (_) => NavController()),
    ],
    child: MaterialApp(
      theme: hustlerTheme(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: screen,
    ),
  ));
  await settle(t);
}

void main() {
  setUp(resetStore);

  group('models', () {
    test('old saves load: client without contact, profile without backup fields', () {
      final c = Client.fromJson({'id': 'x', 'name': 'Old'});
      expect(c.contact, '');
      expect(Client.fromJson((Client(name: 'N', contact: 'Mara')).toJson()).contact, 'Mara');
      final p = Profile.fromJson({'bizName': 'B'});
      expect(p.lastBackup, isNull);
      expect(p.lastBackupBytes, 0);
      final when = DateTime(2026, 10, 11, 9, 41);
      final q = Profile.fromJson((Profile(lastBackup: when, lastBackupBytes: 1234)).toJson());
      expect(q.lastBackup, when);
      expect(q.lastBackupBytes, 1234);
    });
  });

  group('clients tab', () {
    for (final (size, scale) in [(const Size(360, 800), 1.0), (_small, 1.5)]) {
      testWidgets('empty state at $size x$scale', (t) async {
        await pumpScreen(t, const Scaffold(body: ClientsTab()), size: size, textScale: scale);
        expect(find.text('No clients yet'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('long names and balances at $size x$scale', (t) async {
        store.clients = [Client(id: 'a', name: _long, contact: 'Mara Voss with a rather long full name', company: 'Holdings')];
        store.docs = [_inv('1', 'a', 'sent', 123456789.5, due: DateTime.now().add(const Duration(days: 5)))];
        await pumpScreen(t, const Scaffold(body: ClientsTab()), size: size, textScale: scale);
        expect(find.text(_long), findsOneWidget);
        expect(find.text('unpaid'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('search appears for long lists and filters', (t) async {
      store.clients = [for (var i = 0; i < 5; i++) Client(id: 'c$i', name: 'Client $i')];
      await pumpScreen(t, const Scaffold(body: ClientsTab()));
      expect(find.byType(TextField), findsNothing);
      store.clients = [for (var i = 0; i < 8; i++) Client(id: 'c$i', name: i == 3 ? 'Zebra Co' : 'Client $i')];
      store.putClient(store.clients.first); // notify
      await settle(t);
      expect(find.byType(TextField), findsOneWidget);
      await t.enterText(find.byType(TextField), 'zeb');
      await settle(t);
      expect(find.text('Zebra Co'), findsOneWidget);
      expect(find.text('Client 0'), findsNothing);
      await t.enterText(find.byType(TextField), 'nothing like this');
      await settle(t);
      expect(find.text('No matches'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('client detail', () {
    void seed() {
      store.clients = [Client(id: 'a', name: 'Acme', email: 'hi@acme.com', phone: '+91 98765 43210', contact: 'Mara')];
      store.projects = [
        Project(id: 'p1', clientId: 'a', name: 'Site', status: 'review'),
        Project(id: 'p2', clientId: 'a', name: 'App', todos: [Todo(text: 'x', done: true), Todo(text: 'y')]),
      ];
      store.docs = [
        _inv('1', 'a', 'sent', 1000, due: DateTime.now().add(const Duration(days: 9))),
        _inv('2', 'a', 'paid', 500),
        _inv('3', 'a', 'overdue', 200),
        _inv('4', 'a', 'draft', 50),
      ];
    }

    testWidgets('real totals, projects with status, documents', (t) async {
      seed();
      await pumpScreen(t, const ClientDetailPage('a'));
      for (final label in ['BILLED', 'PAID', 'OUTSTANDING', 'OVERDUE']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text(money(1700)), findsOneWidget); // billed: everything but the draft
      expect(find.text(money(1200)), findsOneWidget); // outstanding: sent + overdue
      expect(find.text('1 invoice'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('1/2 tasks · 50%'), findsOneWidget);
      await _scrollTo(t, find.text('DOCUMENTS (4)'));
      expect(find.text('Tax ID'.toUpperCase()), findsNothing); // none set
      expect(t.takeException(), isNull);
    });

    testWidgets('copy email puts it on the clipboard and says so', (t) async {
      seed();
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpScreen(t, const ClientDetailPage('a'));
      await t.tap(find.byTooltip('Copy email'));
      await settle(t);
      expect(copied, 'hi@acme.com');
      expect(find.text('Email copied'), findsOneWidget);
    });

    for (final (size, scale) in [(const Size(360, 800), 1.0), (_small, 1.5)]) {
      testWidgets('long strings and amounts at $size x$scale', (t) async {
        store.clients = [Client(id: 'a', name: _long, contact: _long, email: 'a.very.long.address.${'x' * 60}@example.com', address: 'Line\n' * 8, notes: _long * 3)];
        store.projects = [Project(id: 'p', clientId: 'a', name: _long)];
        store.docs = [
          _inv('1', 'a', 'sent', 12345678912.5, due: DateTime.now().add(const Duration(days: 9))),
          _inv('2', 'a', 'overdue', 98765432.5),
        ];
        await pumpScreen(t, const ClientDetailPage('a'), size: size, textScale: scale);
        expect(t.takeException(), isNull);
        await _scrollTo(t, find.text('Delete client'));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('delete is refused while documents exist, with an explanation', (t) async {
      seed();
      await _open(t, const ClientDetailPage('a'));
      await _scrollTo(t, find.text('Delete client'));
      await t.tap(find.text('Delete client'));
      await settle(t);
      expect(find.textContaining('still has 4 invoices'), findsOneWidget);
      await t.tap(find.text('OK'));
      await settle(t);
      expect(store.client('a'), isNotNull);
    });

    testWidgets('delete names the real project count, then removes client and projects', (t) async {
      store.clients = [Client(id: 'a', name: 'Acme'), Client(id: 'b', name: 'Other')];
      store.projects = [Project(id: 'p1', clientId: 'a', name: 'One'), Project(id: 'p2', clientId: 'a', name: 'Two'), Project(id: 'p3', clientId: 'b', name: 'Three')];
      await _open(t, const ClientDetailPage('a'));
      await _scrollTo(t, find.text('Delete client'));
      await t.tap(find.text('Delete client'));
      await settle(t);
      expect(find.textContaining('also deletes its 2 projects'), findsOneWidget);
      await t.tap(find.text('Delete'));
      await settle(t);
      expect(store.client('a'), isNull);
      expect(store.projects.map((p) => p.id), ['p3']);
    });
  });

  group('client edit', () {
    Future<void> type(WidgetTester t, int field, String text) async {
      await t.enterText(find.byType(TextFormField).at(field), text);
      await t.pump();
    }

    testWidgets('requires a name', (t) async {
      await _open(t, ClientEdit(Client(), isNew: true));
      await t.tap(find.text('Create client'));
      await settle(t);
      expect(find.text('Enter a client name'), findsWidgets);
      expect(store.clients, isEmpty);
    });

    testWidgets('rejects duplicate names (case-insensitive) and bad email/phone', (t) async {
      store.clients = [Client(id: 'a', name: 'Acme')];
      await _open(t, ClientEdit(Client(), isNew: true));
      await type(t, 0, '  acme ');
      await type(t, 2, 'not-an-email');
      await type(t, 3, '12');
      await t.tap(find.text('Create client'));
      await settle(t);
      expect(find.textContaining('already exists'), findsWidgets);
      expect(find.textContaining('valid email'), findsOneWidget);
      expect(find.text('Enter a valid phone number'), findsOneWidget);
      expect(store.clients.length, 1);
    });

    testWidgets('phone field blocks letters', (t) async {
      await _open(t, ClientEdit(Client(), isNew: true));
      await type(t, 3, 'abc+91 (22) 555-1234');
      expect(find.text('+91 (22) 555-1234'), findsOneWidget);
    });

    testWidgets('saves trimmed values, contact and chosen colour', (t) async {
      await _open(t, ClientEdit(Client(), isNew: true));
      await type(t, 0, '  Northwind  ');
      await type(t, 1, ' Mara Voss ');
      await type(t, 2, 'mara@northwind.com');
      await _scrollTo(t, find.text('AVATAR COLOR'));
      await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await t.pump();
      await t.tap(find.bySemanticsLabel('Avatar color 2'));
      await t.pump();
      await t.tap(find.text('Create client'));
      await settle(t);
      expect(store.clients.length, 1);
      final c = store.clients.first;
      expect(c.name, 'Northwind');
      expect(c.contact, 'Mara Voss');
      expect(c.phone, '');
      expect(c.email, 'mara@northwind.com');
      expect(c.colorValue, 0xFF2F7D5B);
    });

    testWidgets('editing keeps own name valid and updates in place', (t) async {
      store.clients = [Client(id: 'a', name: 'Acme', colorValue: 0xFF3B5B8C)];
      await _open(t, ClientEdit(store.clients.first.copy()));
      await type(t, 1, 'Pat');
      await t.tap(find.text('Save changes'));
      await settle(t);
      expect(store.clients.length, 1);
      expect(store.clients.first.contact, 'Pat');
    });

    for (final (size, scale) in [(const Size(360, 800), 1.0), (_small, 1.5)]) {
      testWidgets('renders without overflow at $size x$scale', (t) async {
        await pumpScreen(t, ClientEdit(Client(name: _long, contact: _long), isNew: true), size: size, textScale: scale);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('settings', () {
    for (final (size, scale) in [(const Size(360, 800), 1.0), (_small, 1.5)]) {
      testWidgets('renders everything at $size x$scale, fully scrolled', (t) async {
        store.profile = Profile(bizName: _long, ownerName: _long, address: _long * 2, bank: 'Line\n' * 6, terms: _long * 2, taxId: 'X' * 40);
        await pumpScreen(t, const SettingsPage(), size: size, textScale: scale);
        expect(t.takeException(), isNull);
        await _jumpToEnd(t);
        expect(find.text('About'.toUpperCase()), findsOneWidget);
        expect(t.takeException(), isNull);
        await settle(t, const Duration(seconds: 3)); // let entrance animations that mounted during the jump finish
      });
    }

    testWidgets('nothing invented: no sample IBAN, no encrypted export, no fake backup', (t) async {
      await pumpScreen(t, const SettingsPage());
      expect(find.textContaining('IBAN GB29'), findsNothing);
      expect(find.textContaining('Encrypted'), findsNothing);
      expect(find.textContaining('AES'), findsNothing);
      expect(find.textContaining('14.4 MB'), findsNothing);
      expect(find.textContaining('Vulkan'), findsNothing);
      expect(find.textContaining('NEON'), findsNothing);
      expect(find.textContaining('Never backed up'), findsOneWidget);
      expect(find.text('Back up now'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
    });

    testWidgets('shows the real last backup time and size', (t) async {
      store.profile = Profile(lastBackup: DateTime(2026, 10, 3, 9, 41), lastBackupBytes: 15 * 1024);
      await pumpScreen(t, const SettingsPage());
      expect(find.textContaining('3 Oct 2026, 09:41 · 15.0 KB'), findsOneWidget);
      expect(find.textContaining('Never backed up'), findsNothing);
    });

    testWidgets('typing updates the profile, invalid email is not saved', (t) async {
      await pumpScreen(t, const SettingsPage());
      final fields = find.byType(TextField);
      await _scrollTo(t, find.text('BUSINESS NAME'));
      await t.enterText(fields.at(0), '  Studio Ink ');
      await t.enterText(fields.at(2), 'bad');
      await t.pump();
      expect(find.textContaining('Enter a valid email'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(store.profile.bizName, 'Studio Ink');
      expect(store.profile.email, '');
      await t.enterText(fields.at(2), 'me@studio.com');
      await t.pump(const Duration(seconds: 1));
      expect(store.profile.email, 'me@studio.com');
      // the text survives a rebuild
      store.notifyListeners();
      await t.pump();
      expect(find.text('  Studio Ink '), findsOneWidget);
    });

    testWidgets('currency chip, tax and due days validation', (t) async {
      await pumpScreen(t, const SettingsPage());
      await _scrollTo(t, find.bySemanticsLabel('Currency €'));
      await t.tap(find.bySemanticsLabel('Currency €'));
      await t.pump(const Duration(seconds: 1));
      expect(store.profile.currency, '€');
      await _scrollTo(t, find.text('DEFAULT TAX %'));
      final taxField = find.byType(TextField).at(find.byType(TextField).evaluate().length - 3); // the hourly rate field comes last
      final dueField = find.byType(TextField).at(find.byType(TextField).evaluate().length - 2);
      await t.enterText(taxField, '18');
      await t.enterText(dueField, '30');
      await t.pump(const Duration(seconds: 1));
      expect(store.profile.defaultTax, 18);
      expect(store.profile.dueDays, 30);
      await t.enterText(taxField, '250');
      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('Enter 0 to 100'), findsOneWidget);
      expect(store.profile.defaultTax, 18);
    });

    testWidgets('heuristic switch and hardware toggle persist to the profile', (t) async {
      await pumpScreen(t, const SettingsPage());
      await _scrollTo(t, find.text('CPU'));
      await t.tap(find.text('CPU'));
      await t.pump(const Duration(seconds: 1));
      expect(store.profile.hardware, 'CPU');
      expect(find.textContaining('CPU only'), findsOneWidget);
      await _scrollTo(t, find.byType(Switch));
      await t.tap(find.byType(Switch));
      await t.pump(const Duration(seconds: 1));
      expect(store.profile.heuristicFallback, isTrue);
    });

    for (final (size, scale) in [(const Size(360, 800), 1.0), (_small, 1.5)]) {
      testWidgets('model cards: running/hold, paused, failed, ready render at $size x$scale', (t) async {
        final dl = _FakeDl();
        dl.states['gemma4'] = const DlInfo(Dl.running, progress: .4, hold: 'Waiting for network');
        dl.states['qwen25'] = const DlInfo(Dl.paused, progress: .25);
        await _pumpWith(t, dl, const SettingsPage(), size: size, textScale: scale);
        await _scrollTo(t, find.textContaining('Waiting for network'));
        expect(find.text('Pause'), findsOneWidget);
        await _scrollTo(t, find.textContaining('Paused at 25%'));
        expect(find.text('Resume'), findsOneWidget);
        expect(find.text('Cancel'), findsWidgets);
        expect(t.takeException(), isNull);

        dl.states['gemma4'] = DlInfo(Dl.failed, progress: .4, error: 'Network error ' * 12);
        dl.states['qwen25'] = const DlInfo(Dl.ready);
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        dl.notifyListeners();
        await settle(t);
        await t.drag(find.byType(Scrollable).first, const Offset(0, 5000));
        await t.pump();
        await _scrollTo(t, find.textContaining('Interrupted at 40%'));
        expect(find.text('Resume'), findsOneWidget);
        await _scrollTo(t, find.text('Remove'));
        await settle(t); // let entrance animations created by scrolling finish
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('cancelling a partial download asks first', (t) async {
      final dl = _FakeDl();
      dl.states['gemma4'] = const DlInfo(Dl.paused, progress: .5);
      await _pumpWith(t, dl, const SettingsPage());
      await _scrollTo(t, find.text('Cancel'));
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(find.text('Cancel download?'), findsOneWidget);
      expect(find.textContaining('Discard the'), findsOneWidget);
      await t.tapAt(const Offset(2, 2)); // dismiss; confirming would call the native downloader
      await settle(t);
      expect(find.text('Cancel download?'), findsNothing);
    });
  });
}
