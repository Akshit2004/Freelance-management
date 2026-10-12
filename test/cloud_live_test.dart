// Live round trip against the real MongoDB. Skipped unless HUSTLER_LIVE_MONGO=1, so normal test runs never touch the network or your data.
// Reads the connection string from .env locally, writes to a throwaway collection and drops it again. Never prints the string.
import 'dart:io';

import 'package:freelance_os/cloud_backup.dart';
import 'package:mongo_dart/mongo_dart.dart' show Db;

import 'harness.dart';

void main() {
  final live = Platform.environment['HUSTLER_LIVE_MONGO'] == '1';

  test('upload, rotate and fetch against the real database', () async {
    final line = File('.env').readAsLinesSync().firstWhere((l) => l.startsWith('MONGODB_URI='));
    final uri = line.substring('MONGODB_URI='.length).trim().replaceAll('"', '').replaceAll("'", '');
    final collection = 'selftest_${DateTime.now().millisecondsSinceEpoch}';
    final remote = MongoRemote(uri, collection: collection);
    final cloud = CloudBackup(remote);
    try {
      await cloud.upload('{"round":1,"emoji":"₹ ok"}', clients: 1, projects: 2, docs: 3);
      await cloud.upload('{"round":2}', clients: 4, projects: 5, docs: 6);
      final v = await cloud.versions();
      expect(v.map((b) => b.id), ['latest', 'previous']);
      expect(v.first.json, '{"round":2}');
      expect(v.first.docs, 6);
      expect(v.last.json, '{"round":1,"emoji":"₹ ok"}', reason: 'text comes back byte for byte, including ₹');
      expect(v.first.savedAt.difference(DateTime.now()).inMinutes.abs(), lessThan(2));
    } finally {
      final db = await Db.create(uri);
      db.databaseName = 'hustler';
      await db.open(secure: true);
      await db.dropCollection(collection);
      await db.close();
    }
  }, skip: live ? false : 'set HUSTLER_LIVE_MONGO=1 to run against the real database', timeout: const Timeout(Duration(seconds: 90)));
}
