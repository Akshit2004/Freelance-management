import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:freelance_os/cloud_backup.dart';
import 'package:freelance_os/models.dart';
import 'package:freelance_os/settings.dart';

import 'harness.dart';

class FakeRemote implements BackupRemote {
  final docs = <String, Map<String, dynamic>>{};
  Object? failWith;
  @override
  String get where => 'cluster.example.net/hustler.backups';
  @override
  Future<Map<String, dynamic>?> read(String id) async {
    if (failWith != null) throw failWith!;
    final d = docs[id];
    return d == null ? null : Map<String, dynamic>.from(d);
  }

  @override
  Future<void> write(String id, Map<String, dynamic> doc) async {
    if (failWith != null) throw failWith!;
    docs[id] = {...doc, '_id': id};
  }
}

/// Scrolls [f] to the middle of the screen (ensureVisible alone can leave it under the app bar).
Future<void> centre(WidgetTester t, Finder f) async {
  await Scrollable.ensureVisible(t.element(f), alignment: .5);
  await t.pump();
}

void main() {
  tearDown(() => CloudBackup.instance = null);

  group('CloudBackup', () {
    test('keeps the newest copy and the one before it, and restores the exact text', () async {
      final r = FakeRemote();
      final c = CloudBackup(r);
      await c.upload('{"v":1}', clients: 1, projects: 0, docs: 0);
      expect(r.docs.keys, ['latest']);
      await c.upload('{"v":2}', clients: 2, projects: 1, docs: 3);
      await c.upload('{"v":3}', clients: 3, projects: 1, docs: 3);
      expect(r.docs['latest']!['data'], '{"v":3}');
      expect(r.docs['previous']!['data'], '{"v":2}', reason: 'only one older copy is kept');
      final v = await c.versions();
      expect(v.map((b) => b.id), ['latest', 'previous']);
      expect(v.first.json, '{"v":3}');
      expect(v.first.clients, 3);
      expect(v.first.bytes, 7);
    });

    test('a failed upload leaves the last good copy alone', () async {
      final r = FakeRemote();
      final c = CloudBackup(r);
      await c.upload('{"good":true}', clients: 1, projects: 0, docs: 0);
      r.failWith = TimeoutException('x');
      await expectLater(c.upload('{"bad":true}', clients: 0, projects: 0, docs: 0), throwsA(isA<CloudBackupException>()));
      r.failWith = null;
      expect((await c.versions()).first.json, '{"good":true}');
    });

    test('errors are readable and never contain the password', () {
      expect(CloudBackup.friendly(TimeoutException('t')), contains('Network Access'));
      expect(CloudBackup.friendly(Exception('Authentication failed')), contains('refused the login'));
      final leaked = CloudBackup.friendly(Exception('cannot parse mongodb+srv://bob:s3cret@cluster0.abc.mongodb.net/x'));
      expect(leaked, isNot(contains('s3cret')));
      expect(leaked, isNot(contains('bob')));
    });

    test('connection string validation', () {
      expect(CloudBackup.validate(''), isNotNull);
      expect(CloudBackup.validate('https://example.com'), contains('mongodb'));
      expect(CloudBackup.validate('mongodb+srv://a b@c'), contains('spaces'));
      expect(CloudBackup.validate('mongodb+srv://user:pw@cluster0.abc.mongodb.net'), isNull);
      expect(CloudBackup.validate('  mongodb://localhost:27017  '), isNull);
    });

    test('the displayed host never includes credentials', () {
      CloudBackup.configure('mongodb+srv://bob:s3cret@cluster0.abc.mongodb.net');
      expect(CloudBackup.instance!.host, 'cluster0.abc.mongodb.net');
      expect(CloudBackup.instance!.remote.where, isNot(contains('s3cret')));
    });
  });

  group('Store backup tracking', () {
    test('needsBackup follows real changes, and recording a backup is not a change', () async {
      resetStore();
      expect(store.needsBackup, false, reason: 'no data, nothing to back up');
      store.putClient(Client(name: 'Acme'));
      expect(store.needsBackup, true);
      store.markBackedUp(123);
      expect(store.profile.lastBackupBytes, 123);
      expect(store.needsBackup, false);
      store.putClient(Client(name: 'Zed'));
      expect(store.needsBackup, true);
    });

    test('auto-backup uploads only when enabled, changed, and not within 10 minutes of the last one', () async {
      resetStore();
      final r = FakeRemote();
      final c = CloudBackup(r);
      store.putClient(Client(name: 'Acme'));
      await c.autoBackUp(store);
      expect(r.docs, isEmpty, reason: 'off by default');
      store.profile.autoBackup = true;
      await c.autoBackUp(store);
      expect(r.docs.keys, ['latest']);
      store.putClient(Client(name: 'Zed'));
      await c.autoBackUp(store);
      expect(r.docs['previous'], isNull, reason: 'a backup 0 minutes ago is not repeated');
      store.profile.lastBackup = DateTime.now().subtract(const Duration(minutes: 11));
      await c.autoBackUp(store);
      expect(r.docs['previous'], isNotNull);
    });
  });

  group('Settings screen', () {
    testWidgets('without MongoDB: offers to connect, keeps the file backup', (t) async {
      resetStore();
      await pumpScreen(t, const SettingsPage());
      expect(find.text('MongoDB not connected'), findsOneWidget);
      expect(find.text('Connect MongoDB'), findsOneWidget);
      expect(find.text('Back up now'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('with MongoDB: backs up and restores through it, file export stays available', (t) async {
      resetStore();
      final r = FakeRemote();
      CloudBackup.instance = CloudBackup(r);
      store.putClient(Client(name: 'Acme'));
      await pumpScreen(t, const SettingsPage());
      expect(find.textContaining('Connected to'), findsOneWidget);
      expect(find.text('Back up to MongoDB'), findsOneWidget);
      expect(find.text('Restore from MongoDB'), findsOneWidget);
      expect(find.text('Export file'), findsOneWidget);
      await centre(t, find.text('Back up to MongoDB'));
      await t.tap(find.text('Back up to MongoDB'));
      await settle(t);
      expect(r.docs['latest'], isNotNull);
      expect(r.docs['latest']!['clients'], 1);
      expect(store.profile.lastBackup, isNotNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('a failing connection shows a readable message, not a stack trace', (t) async {
      resetStore();
      final r = FakeRemote()..failWith = TimeoutException('slow');
      CloudBackup.instance = CloudBackup(r);
      await pumpScreen(t, const SettingsPage());
      await centre(t, find.text('Back up to MongoDB'));
      await t.tap(find.text('Back up to MongoDB'));
      await settle(t);
      expect(find.textContaining('Network Access'), findsOneWidget);
    });

    testWidgets('card text fits at 320dp / 1.5x', (t) async {
      resetStore();
      CloudBackup.instance = CloudBackup(FakeRemote());
      await pumpScreen(t, const SettingsPage(), size: const Size(320, 568), textScale: 1.5);
      expect(t.takeException(), isNull);
    });
  });
}
