import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mongo_dart/mongo_dart.dart' show Db, DbCollection, SelectorBuilder;

import 'log.dart';
import 'models.dart';

/// One saved copy of the whole database, as stored in MongoDB.
class RemoteBackup {
  final String id; // 'latest' or 'previous'
  final DateTime savedAt;
  final int bytes, clients, projects, docs;
  final String json;
  const RemoteBackup({required this.id, required this.savedAt, required this.bytes, required this.clients, required this.projects, required this.docs, required this.json});

  factory RemoteBackup.fromDoc(Map<String, dynamic> d) => RemoteBackup(
        id: '${d['_id']}',
        savedAt: DateTime.tryParse('${d['savedAt']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
        bytes: (d['bytes'] as num?)?.toInt() ?? 0,
        clients: (d['clients'] as num?)?.toInt() ?? 0,
        projects: (d['projects'] as num?)?.toInt() ?? 0,
        docs: (d['docs'] as num?)?.toInt() ?? 0,
        json: '${d['data']}',
      );
}

/// Storage seam: MongoDB in the app, an in-memory map in tests.
abstract class BackupRemote {
  Future<Map<String, dynamic>?> read(String id);
  Future<void> write(String id, Map<String, dynamic> doc);
  String get where; // for log lines: host + collection, never credentials
}

/// MongoDB over TLS (`mongodb+srv://`), using the URI from `.env`. Connects per call and closes again, so nothing stays open in the background.
class MongoRemote implements BackupRemote {
  MongoRemote(this.uri, {this.database = 'hustler', this.collection = 'backups'});
  final String uri;
  final String database, collection;

  @override
  String get where => '${Uri.tryParse(uri.replaceFirst('mongodb+srv://', 'https://'))?.host ?? 'mongodb'}/$database.$collection';

  Future<T> _run<T>(Future<T> Function(DbCollection c) body) async {
    final db = await Db.create(uri).timeout(const Duration(seconds: 15));
    db.databaseName = database; // the URI usually has no database name; this keeps our data in its own database
    try {
      await db.open(secure: true).timeout(const Duration(seconds: 20));
      return await body(db.collection(collection)).timeout(const Duration(seconds: 30));
    } finally {
      try {
        await db.close();
      } catch (_) {}
    }
  }

  @override
  Future<Map<String, dynamic>?> read(String id) => _run((c) => c.findOne(_byId(id)));

  @override
  Future<void> write(String id, Map<String, dynamic> doc) => _run((c) async {
        final r = await c.replaceOne(_byId(id), Map<String, dynamic>.from(doc)..remove('_id'), upsert: true); // insert or replace by _id
        if (!r.isSuccess) throw StateError('MongoDB did not accept the write: ${r.writeError?.errmsg ?? r.errmsg ?? 'unknown error'}');
      });

  static SelectorBuilder _byId(String id) => SelectorBuilder().eq('_id', id);
}

/// Cloud backup of the local database in MongoDB: the newest copy plus the one before it, so a bad upload never destroys the last good one.
class CloudBackup {
  CloudBackup(this.remote);
  final BackupRemote remote;

  /// Set once at startup when `.env` has a MONGODB_URI; null means cloud backup isn't configured.
  static CloudBackup? instance;
  static bool get configured => instance != null;

  static const _key = 'mongodb_uri';
  static const _storage = FlutterSecureStorage();

  /// Loads the connection string saved in Settings (Android Keystore-backed storage). Call once at startup.
  static Future<void> load() async {
    try {
      configure(await _storage.read(key: _key));
    } catch (_) {
      configure(null);
    }
  }

  /// Why [raw] can't be a MongoDB connection string, or null if it looks right.
  static String? validate(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return 'Paste your MongoDB connection string.';
    if (!u.startsWith('mongodb+srv://') && !u.startsWith('mongodb://')) return 'It should start with mongodb+srv:// or mongodb://';
    if (u.contains(' ')) return 'A connection string has no spaces.';
    if (Uri.tryParse(u.replaceFirst('mongodb+srv://', 'https://').replaceFirst('mongodb://', 'https://')) == null) return 'That is not a valid address (special characters in the password must be percent-encoded).';
    return null;
  }

  /// Tries the connection (reads the backups collection); throws [CloudBackupException] with a readable reason if it can't.
  static Future<void> test(String uri) async => CloudBackup(MongoRemote(uri.trim())).versions();

  static Future<void> save(String uri) async {
    await _storage.write(key: _key, value: uri.trim());
    configure(uri);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _key);
    configure(null);
  }

  /// Where backups go, for display: the server name only, never the credentials.
  String get host => remote.where.split('/').first;

  static void configure(String? uri) {
    final u = uri?.trim().replaceAll('"', '').replaceAll("'", '');
    instance = (u == null || u.isEmpty) ? null : CloudBackup(MongoRemote(u));
  }

  /// Saves [json] as the newest backup, moving the current newest to "previous" first.
  Future<RemoteBackup> upload(String json, {required int clients, required int projects, required int docs}) async {
    final sw = Stopwatch()..start();
    final bytes = utf8.encode(json).length;
    try {
      final current = await remote.read('latest');
      if (current != null) await remote.write('previous', Map<String, dynamic>.from(current)..remove('_id'));
      final doc = <String, dynamic>{
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'schema': 1,
        'bytes': bytes,
        'clients': clients,
        'projects': projects,
        'docs': docs,
        'data': json, // kept as one string: no BSON key restrictions, restored byte for byte
      };
      await remote.write('latest', doc);
      Log.net('POST   mongodb ${remote.where}  backup ${_kb(bytes)}  ${sw.elapsedMilliseconds} ms');
      return RemoteBackup.fromDoc({...doc, '_id': 'latest'});
    } catch (e) {
      Log.net('POST   mongodb ${remote.where}  backup FAILED  ${friendly(e)}');
      throw CloudBackupException(friendly(e));
    }
  }

  /// Backs up everything in [s] and records it (time + size) on the profile. Used by the Settings button and by auto-backup.
  Future<RemoteBackup> backUp(Store s) async {
    await s.flush();
    final json = s.exportJson();
    final saved = await upload(json, clients: s.clients.length, projects: s.projects.length, docs: s.docs.length);
    s.markBackedUp(saved.bytes);
    return saved;
  }

  bool _running = false;

  /// Quiet backup, used every 5 minutes while the app is open and when it goes to the background: only if enabled, something changed
  /// and the last one is 4+ minutes old. True when a backup was saved.
  Future<bool> autoBackUp(Store s) async {
    if (_running || !s.profile.autoBackup || !s.needsBackup) return false;
    final last = s.profile.lastBackup;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 4)) return false;
    _running = true;
    try {
      await backUp(s);
      return true;
    } catch (_) {
      return false; // already logged; the next tick tries again
    } finally {
      _running = false;
    }
  }

  /// The saved copies, newest first (empty if nothing has been backed up yet).
  Future<List<RemoteBackup>> versions() async {
    final sw = Stopwatch()..start();
    try {
      final out = <RemoteBackup>[];
      for (final id in const ['latest', 'previous']) {
        final d = await remote.read(id);
        if (d != null) out.add(RemoteBackup.fromDoc(d..['_id'] = id));
      }
      Log.net('GET    mongodb ${remote.where}  ${out.length} backups  ${sw.elapsedMilliseconds} ms');
      return out;
    } catch (e) {
      Log.net('GET    mongodb ${remote.where}  FAILED  ${friendly(e)}');
      throw CloudBackupException(friendly(e));
    }
  }

  static String _kb(int b) => b < 1024 ? '$b B' : '${(b / 1024).toStringAsFixed(1)} KB';

  /// A message a person can act on, with any credentials removed.
  static String friendly(Object e) {
    final raw = e.toString().replaceAll(RegExp(r'://[^@\s/]+@'), '://***@');
    final l = raw.toLowerCase();
    if (e is TimeoutException || l.contains('timed out') || l.contains('timeout')) {
      return 'Could not reach MongoDB in time. Check your internet, and that MongoDB Atlas › Network Access allows this phone (for example 0.0.0.0/0).';
    }
    if (l.contains('auth') || l.contains('unauthorized') || l.contains('not authorized')) {
      return 'MongoDB refused the login in .env (wrong user, password or permissions).';
    }
    if (l.contains('socket') || l.contains('dns') || l.contains('lookup') || l.contains('network is unreachable') || l.contains('connection')) {
      return 'No connection to MongoDB. Check your internet and the address in .env.';
    }
    return 'MongoDB error: ${raw.length > 160 ? '${raw.substring(0, 160)}…' : raw}';
  }
}

class CloudBackupException implements Exception {
  final String message;
  CloudBackupException(this.message);
  @override
  String toString() => message;
}
