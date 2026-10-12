import 'package:flutter/material.dart';
import 'package:freelance_os/models.dart';
import 'package:freelance_os/projects.dart';

import 'harness.dart';

const _long = 'An extraordinarily long project name that keeps going and going to prove that nothing overflows on a small phone';

/// Page row -> detail sheet -> its Edit button -> edit sheet.
Future<void> _openEdit(WidgetTester t, String id) async {
  await t.tap(find.byKey(Key('edit-$id')), warnIfMissed: false);
  await settle(t);
  await t.tap(find.byKey(const Key('detail-edit')));
  await settle(t);
}

Future<void> _closeDetail(WidgetTester t) async {
  Navigator.of(t.element(find.byKey(const Key('detail-edit')))).pop();
  await settle(t);
}

void _seed() {
  resetStore();
  store.clients = [
    Client(id: 'c1', name: 'Acme Studio'),
    Client(id: 'c2', name: 'Very Long Client Name Incorporated Holdings Worldwide Limited'),
  ];
  store.projects = [
    Project(
      id: 'p1',
      clientId: 'c1',
      name: 'Brand refresh',
      budget: 100000,
      deadline: DateTime.now().add(const Duration(days: 3)),
      todos: [
        Todo(id: 't1', text: 'Logo concepts', priority: 'high', hours: '10h'),
        Todo(id: 't2', text: 'Style guide', hours: '4h', sub: [
          Todo(id: 's1', text: 'Colours', hours: '1.5h'),
          Todo(id: 's2', text: 'Type', done: true),
        ]),
      ],
    ),
    Project(id: 'p2', clientId: 'c2', name: _long, status: 'review', todos: [Todo(id: 't3', text: _long * 2)]),
    Project(id: 'p3', clientId: 'c1', name: 'Empty one'), // zero tasks, no budget
    Project(id: 'p4', clientId: 'c1', name: 'Shipped', status: 'done'),
  ];
  store.docs = [
    Doc(id: 'd1', kind: 'invoice', number: 'INV-1', clientId: 'c1', projectId: 'p1', status: 'paid', items: [LineItem(desc: 'x', rate: 30000)]),
    Doc(id: 'd2', kind: 'invoice', number: 'INV-2', clientId: 'c1', projectId: 'p1', status: 'sent', items: [LineItem(desc: 'x', rate: 20000)]),
    Doc(id: 'd3', kind: 'invoice', number: 'INV-3', clientId: 'c1', projectId: 'p1', status: 'draft', items: [LineItem(desc: 'x', rate: 999)]),
    Doc(id: 'd4', kind: 'quote', number: 'QT-1', clientId: 'c1', projectId: 'p1', title: 'Phase two', items: [LineItem(desc: 'x', rate: 1)]),
  ];
  store.baseline();
}

Future<void> _scrollAll(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await t.pump();
  }
}

void main() {
  group('model helpers', () {
    test('hours parse and sum without double counting subtasks', () {
      _seed();
      final p = store.project('p1')!;
      expect(Todo(text: 'a', hours: '14h').hoursValue, 14);
      expect(Todo(text: 'a', hours: '1,5h').hoursValue, 1.5);
      expect(Todo(text: 'a', hours: 'soon').hoursValue, 0);
      expect(Todo.fmtHours(1.5), '1.5h');
      expect(p.hoursEstimate, 11.5); // 10 + (1.5 + 0 of the subtasks), parent's own 4h ignored
    });

    test('billing derives from linked invoices only; drafts and quotes do not count', () {
      _seed();
      expect(store.projectInvoiced('p1'), 50000);
      expect(store.projectPaid('p1'), 30000);
      expect(store.projectInvoiced('p3'), 0);
      expect(store.docsOfProject('p1').length, 4);
    });

    test('deadline labels', () {
      final now = DateTime(2026, 10, 11, 15);
      String? l(int days) => Project(deadline: DateTime(2026, 10, 11 + days, 9)).deadlineLabel(now);
      expect(l(0), 'Due today');
      expect(l(1), 'Due tomorrow');
      expect(l(5), 'Due in 5 days');
      expect(l(-1), 'Overdue by 1 day');
      expect(l(-4), 'Overdue by 4 days');
      expect(Project().deadlineLabel(now), isNull);
      expect(Project(status: 'done', deadline: DateTime(2020)).isLate(now), isFalse);
    });

    test('intents: edit, add sub, delete keep parents consistent', () {
      _seed();
      store.addSub('p1', 't1', Todo(id: 'n1', text: 'Sketch'));
      expect(store.project('p1')!.todos.first.sub.length, 1);
      store.editTodo('p1', 'n1', text: 'Sketches', hours: '2h');
      expect(store.project('p1')!.todos.first.sub.first.text, 'Sketches');
      store.toggleSub('p1', 't1', 'n1');
      expect(store.project('p1')!.todos.first.done, isTrue);
      store.deleteTodo('p1', 'n1');
      expect(store.project('p1')!.todos.first.sub, isEmpty);
      store.deleteTodo('p1', 't2');
      expect(store.project('p1')!.todos.length, 1);
    });
  });

  group('ProjectsTab', () {
    for (final (size, scale) in [(const Size(360, 800), 1.0), (const Size(320, 568), 1.5)]) {
      testWidgets('renders every stage without overflow at $size x$scale', (t) async {
        _seed();
        await pumpScreen(t, const ProjectsTab(), size: size, textScale: scale);
        expect(t.takeException(), isNull);
        expect(find.text('Brand refresh'), findsOneWidget);
        expect(find.textContaining('Due in 3 days'), findsOneWidget);
        expect(find.textContaining('Next: Logo concepts'), findsOneWidget);
        for (final s in ['Review', 'Done']) {
          await t.tap(find.text(s));
          await settle(t);
          expect(t.takeException(), isNull);
        }
      });
    }

    testWidgets('filter counts and zero-task project show 0% not NaN', (t) async {
      _seed();
      await pumpScreen(t, const ProjectsTab());
      expect(find.text('2'), findsOneWidget); // active: p1 + p3
      expect(find.text('DONE 0%'), findsOneWidget);
      expect(find.text('NO TASKS YET'), findsOneWidget);
      expect(find.textContaining('NaN'), findsNothing);
      await t.tap(find.text('Done'));
      await settle(t);
      expect(find.text('Shipped'), findsOneWidget);
    });

    testWidgets('empty states', (t) async {
      resetStore();
      await pumpScreen(t, const ProjectsTab());
      expect(find.text('No projects yet'), findsOneWidget);
      expect(find.text('New project'), findsWidgets);
      store.projects = [Project(id: 'x', name: 'Only active')];
      store.save();
      await t.tap(find.text('Review'));
      await settle(t);
      expect(find.text('Nothing in Review'), findsOneWidget);
    });

    testWidgets('unknown status lands under Active', (t) async {
      resetStore();
      store.clients = [Client(id: 'c', name: 'A')];
      store.projects = [Project(id: 'x', clientId: 'c', name: 'Odd', status: 'archived')];
      await pumpScreen(t, const ProjectsTab());
      expect(find.text('Odd'), findsOneWidget);
    });
  });

  group('ProjectDetailPage', () {
    for (final (size, scale) in [(const Size(360, 800), 1.0), (const Size(320, 568), 1.5)]) {
      testWidgets('no overflow at $size x$scale, including long names', (t) async {
        _seed();
        await pumpScreen(t, const ProjectDetailPage('p1'), size: size, textScale: scale);
        await _scrollAll(t);
        expect(t.takeException(), isNull);
        store.putProject(store.project('p2')!);
        await pumpScreen(t, const ProjectDetailPage('p2'), size: size, textScale: scale);
        await _scrollAll(t);
        expect(t.takeException(), isNull);
        await pumpScreen(t, const ProjectDetailPage('p3'), size: size, textScale: scale);
        await _scrollAll(t);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('shows real billing, linked documents and empty states', (t) async {
      _seed();
      await pumpScreen(t, const ProjectDetailPage('p1'), size: const Size(360, 1800));
      expect(find.text('₹1,00,000'), findsOneWidget); // budget
      expect(find.text('₹50,000'), findsWidgets); // invoiced (drafts excluded)
      expect(find.text('₹30,000'), findsWidgets); // paid
      expect(find.text('₹20,000'), findsWidgets); // awaiting
      expect(find.text('INV-1', skipOffstage: false), findsNothing); // shown as "INVOICE · INV-1"
      expect(find.textContaining('INVOICE · INV-1'), findsOneWidget);
      expect(find.textContaining('QUOTE · QT-1'), findsOneWidget);
      expect(find.text('Phase two'), findsOneWidget);
      expect(find.text('High'), findsOneWidget); // priority is text, not only a dot
      expect(find.text('Acme Studio'), findsOneWidget);

      await pumpScreen(t, const ProjectDetailPage('p3'), size: const Size(360, 1800));
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.textContaining('No budget set'), findsOneWidget);
      expect(find.textContaining('No deliverables yet'), findsOneWidget);
      expect(find.textContaining('No invoices or quotes'), findsOneWidget);
      expect(find.text('No deadline set'), findsOneWidget);
    });

    testWidgets('toggling tasks goes through the store', (t) async {
      _seed();
      await pumpScreen(t, const ProjectDetailPage('p1'), size: const Size(360, 1800));
      await t.tap(find.byKey(const Key('toggle-t1')));
      await settle(t);
      expect(store.project('p1')!.todos.first.done, isTrue);
      expect(find.byKey(const Key('toggle-s1')), findsNothing, reason: 'subtasks are listed in the detail sheet, not on the page');
      expect(find.text('1/2 subtasks'), findsOneWidget);
      await t.tap(find.byKey(const Key('edit-t2')), warnIfMissed: false);
      await settle(t);
      expect(find.text('Colours'), findsOneWidget);
      await t.tap(find.byKey(const Key('toggle-s1')));
      await settle(t);
      expect(store.project('p1')!.todos[1].done, isTrue); // both subtasks done -> parent done
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('add deliverable validates name and hours', (t) async {
      _seed();
      await pumpScreen(t, const ProjectDetailPage('p3'), size: const Size(360, 800));
      await t.tap(find.byKey(const Key('add-task')));
      await settle(t);
      await t.tap(find.byKey(const Key('task-save')));
      await settle(t);
      expect(find.text('Give it a name'), findsOneWidget);
      await t.enterText(find.byKey(const Key('task-text')), 'Wireframes');
      await t.enterText(find.byKey(const Key('task-hours')), 'abc');
      await t.tap(find.byKey(const Key('task-save')));
      await settle(t);
      expect(find.textContaining('Enter hours as a number'), findsOneWidget);
      expect(store.project('p3')!.todos, isEmpty);
      await t.enterText(find.byKey(const Key('task-hours')), '2,5');
      await t.tap(find.byKey(const Key('task-save')));
      await settle(t);
      final added = store.project('p3')!.todos.single;
      expect(added.text, 'Wireframes');
      expect(added.hours, '2.5h');
      expect(find.text('Wireframes'), findsOneWidget);
      expect(find.text('2.5h'), findsWidgets);
    });

    testWidgets('a deliverable opens a detail sheet with its subtasks; edit, add subtask and delete go from there', (t) async {
      _seed();
      await pumpScreen(t, const ProjectDetailPage('p1'), size: const Size(360, 1800));
      await t.tap(find.byKey(const Key('edit-t2')), warnIfMissed: false);
      await settle(t);
      expect(find.byKey(const Key('task-text')), findsNothing, reason: 'tapping a deliverable shows the detail first, not the edit form');
      expect(find.text('Colours'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('1/2 subtasks done'), findsOneWidget);
      await _closeDetail(t);

      await _openEdit(t, 't1');
      await t.enterText(find.byKey(const Key('task-text')), 'Logo final');
      await t.tap(find.text('Low'));
      await t.tap(find.byKey(const Key('task-save')));
      await settle(t);
      await _closeDetail(t);
      var t1 = store.project('p1')!.todos.first;
      expect(t1.text, 'Logo final');
      expect(t1.priority, 'low');
      expect(find.text('Low'), findsOneWidget);

      await _openEdit(t, 't1');
      await t.tap(find.byKey(const Key('task-add-sub')));
      await settle(t);
      await t.enterText(find.byKey(const Key('task-text')), 'Mono version');
      await t.tap(find.byKey(const Key('task-save')));
      await settle(t);
      t1 = store.project('p1')!.todos.first;
      expect(t1.sub.single.text, 'Mono version');
      expect(find.text('Mono version'), findsOneWidget, reason: 'the detail sheet is still open and shows the new subtask');
      await t.tap(find.byKey(const Key('detail-add-sub')));
      await settle(t);
      await t.enterText(find.byKey(const Key('task-text')), 'Print version');
      await t.tap(find.byKey(const Key('task-save')));
      await settle(t);
      expect(store.project('p1')!.todos.first.sub.map((x) => x.text), ['Mono version', 'Print version']);
      await _closeDetail(t);

      await _openEdit(t, 't1');
      await t.tap(find.byKey(const Key('task-delete')));
      await settle(t);
      await t.tap(find.text('Delete').last);
      await settle(t);
      expect(store.project('p1')!.todos.any((x) => x.id == 't1'), isFalse);
      expect(find.byKey(const Key('detail-edit')), findsNothing, reason: 'the detail sheet closes with the deleted deliverable');
      expect(t.takeException(), isNull);
    });

    testWidgets('the deliverable detail sheet does not overflow at 320 x 568, 1.5x text', (t) async {
      _seed();
      store.putProject(store.project('p2')!);
      await pumpScreen(t, const ProjectDetailPage('p1'), size: const Size(320, 568), textScale: 1.5);
      await t.scrollUntilVisible(find.byKey(const Key('edit-t2')), 200, scrollable: find.byType(Scrollable).first);
      await t.ensureVisible(find.byKey(const Key('edit-t2')));
      await t.pump();
      await t.tap(find.byKey(const Key('edit-t2')));
      await settle(t);
      expect(find.byKey(const Key('detail-edit')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('status selector changes the project', (t) async {
      _seed();
      await pumpScreen(t, const ProjectDetailPage('p1'));
      await t.tap(find.text('Review'));
      await settle(t);
      expect(store.project('p1')!.status, 'review');
    });

    testWidgets('new invoice button creates a document for this client and project', (t) async {
      _seed();
      await pumpScreen(t, const ProjectDetailPage('p1'), size: const Size(360, 1800));
      await t.tap(find.byKey(const Key('new-invoice')));
      await settle(t);
      expect(find.text('New invoice'), findsWidgets); // DocEditor title
      t.takeException(); // any layout issue inside DocEditor belongs to docs.dart's own tests
    });

    testWidgets('client chip opens the client', (t) async {
      _seed();
      await pumpScreen(t, const ProjectDetailPage('p1'));
      await t.tap(find.byKey(const Key('client-chip')));
      await settle(t);
      expect(find.text('Acme Studio'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('delete confirms, keeps invoices but unlinks them', (t) async {
      _seed();
      await pumpScreen(t, const ProjectDetailPage('p1'));
      await t.tap(find.byTooltip('Delete project'));
      await settle(t);
      expect(find.textContaining('kept, but will no longer be linked'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(store.project('p1'), isNotNull);
      await t.tap(find.byTooltip('Delete project'));
      await settle(t);
      await t.tap(find.text('Delete').last);
      await settle(t);
      expect(store.project('p1'), isNull);
      expect(store.docs.length, 4);
      expect(store.docs.every((d) => d.projectId == null), isTrue);
    });

    testWidgets('missing project shows a message', (t) async {
      resetStore();
      await pumpScreen(t, const ProjectDetailPage('nope'));
      expect(find.text('Project not found'), findsOneWidget);
    });
  });

  group('ProjectEdit', () {
    testWidgets('layout at small size and big text', (t) async {
      _seed();
      await pumpScreen(t, ProjectEdit(store.project('p2')!), size: const Size(320, 568), textScale: 1.5);
      await _scrollAll(t);
      expect(t.takeException(), isNull);
    });

    testWidgets('validation messages and successful create', (t) async {
      _seed();
      await pumpScreen(t, ProjectEdit(Project(), isNew: true));
      await t.tap(find.byKey(const Key('project-save')));
      await settle(t);
      expect(find.text('Give the project a name'), findsWidgets); // inline error + toast
      expect(find.text('Choose a client'), findsWidgets);
      expect(store.projects.length, 4);

      await t.enterText(find.byKey(const Key('project-name')), 'New site');
      await t.enterText(find.byKey(const Key('project-budget')), '12x');
      await t.tap(find.byKey(const Key('project-save')));
      await settle(t);
      expect(find.textContaining('Enter an amount'), findsOneWidget);

      await t.enterText(find.byKey(const Key('project-budget')), '2,500.50');
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await settle(t);
      await t.tap(find.text('Acme Studio').last);
      await settle(t);
      await t.tap(find.byKey(const Key('project-save')));
      await settle(t);
      expect(store.projects.length, 5);
      final p = store.projects.first;
      expect((p.name, p.clientId, p.budget), ('New site', 'c1', 2500.5));
    });

    testWidgets('editing commits a draft only on save', (t) async {
      _seed();
      final original = store.project('p1')!;
      await pumpScreen(t, ProjectEdit(original));
      await t.enterText(find.byKey(const Key('project-name')), 'Renamed');
      expect(store.project('p1')!.name, 'Brand refresh'); // draft not applied yet
      await t.tap(find.byKey(const Key('project-save')));
      await settle(t);
      expect(store.project('p1')!.name, 'Renamed');
      expect(store.projects.length, 4);
    });

    testWidgets('no clients: says so and offers to add one', (t) async {
      resetStore();
      await pumpScreen(t, ProjectEdit(Project(), isNew: true));
      expect(find.textContaining('no clients yet'), findsOneWidget);
      expect(find.byKey(const Key('add-client')), findsOneWidget);
      await t.enterText(find.byKey(const Key('project-name')), 'X');
      await t.tap(find.byKey(const Key('project-save')));
      await settle(t);
      expect(store.projects, isEmpty);
    });

    testWidgets('deadline can be cleared', (t) async {
      _seed();
      await pumpScreen(t, ProjectEdit(store.project('p1')!));
      await t.tap(find.byKey(const Key('clear-deadline')));
      await settle(t);
      expect(find.text('No deadline'), findsOneWidget);
      await t.tap(find.byKey(const Key('project-save')));
      await settle(t);
      expect(store.project('p1')!.deadline, isNull);
    });
  });
}
