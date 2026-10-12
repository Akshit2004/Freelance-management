import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart' show FileDownloader, PermissionStatus, PermissionType;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'ai.dart';
import 'cloud_backup.dart';
import 'downloads.dart';
import 'models.dart';
import 'motion.dart';
import 'ui.dart';

String fmtBytes(num b) {
  if (b < 1024) return '${b.round()} B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1e9) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(b / 1e9).toStringAsFixed(1)} GB';
}

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');
final _upiRe = RegExp(r'^[\w.\-]{2,}@[A-Za-z][A-Za-z0-9.]{1,}$');

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Store _s = context.read<Store>();
  final _c = <String, TextEditingController>{};
  late Future<int> _bytes = _s.dataBytes();
  bool _busy = false;
  bool _notifDenied = false;
  String? _restoreError;

  Profile get p => _s.profile;

  static const _keys = ['biz', 'owner', 'email', 'phone', 'address', 'tax', 'upi', 'bank', 'terms', 'defTax', 'due', 'rate'];

  @override
  void initState() {
    super.initState();
    for (final k in _keys) {
      _c[k] = TextEditingController();
    }
    _sync();
    _checkNotifications();
  }

  /// Copies the profile into the text controllers (also after a restore replaced it).
  void _sync() {
    final v = {
      'biz': p.bizName,
      'owner': p.ownerName,
      'email': p.email,
      'phone': p.phone,
      'address': p.address,
      'tax': p.taxId,
      'upi': p.upi,
      'bank': p.bank,
      'terms': p.terms,
      'defTax': p.defaultTax == 0 ? '0' : numText(p.defaultTax),
      'due': '${p.dueDays}',
      'rate': p.hourlyRate == 0 ? '' : numText(p.hourlyRate),
    };
    v.forEach((k, t) => _c[k]!.text = t);
  }

  @override
  void dispose() {
    _s.flush();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkNotifications() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final st = await FileDownloader().permissions.status(PermissionType.notifications);
      if (mounted) setState(() => _notifDenied = st != PermissionStatus.granted);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ backup / restore

  Future<void> _backup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _s.flush();
      final dir = await getTemporaryDirectory();
      final name = 'hustler-backup-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json';
      final f = File('${dir.path}/$name');
      await f.writeAsString(_s.exportJson(), flush: true);
      final size = await f.length();
      final r = await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'application/json')],
        subject: 'Hustler backup',
      ));
      if (!mounted) return;
      if (r.status == ShareResultStatus.dismissed) {
        toast(context, 'Backup cancelled. Nothing was saved.');
      } else {
        _s.updateProfile((p) {
          p.lastBackup = DateTime.now();
          p.lastBackupBytes = size;
        });
        toast(context, 'Backup ready: $name');
      }
    } catch (e) {
      if (mounted) toast(context, 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for the connection string, tests it, and keeps it in encrypted storage.
  Future<void> _connectMongo() async {
    final uri = await showDialog<String>(context: context, builder: (_) => const _MongoDialog());
    if (uri == null || !mounted) return;
    setState(() {});
    toast(context, 'MongoDB connected. Back up whenever you like.');
  }

  Widget _mongoCard() {
    final cloud = CloudBackup.instance;
    return CardContainer(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(cloud == null ? Icons.cloud_off_rounded : Icons.cloud_done_rounded, color: cloud == null ? C.muted : C.green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(cloud == null ? 'MongoDB not connected' : 'Connected to ${cloud.host}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            cloud == null
                ? 'Back up to your own MongoDB (Atlas). Paste your connection string once. It is kept in this phone\'s encrypted storage: it is never inside the app file or in a backup.'
                : 'Backups go to database "hustler", collection "backups". The connection string is kept in this phone\'s encrypted storage.',
            style: const TextStyle(fontSize: 11.5, color: C.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _btn(cloud == null ? 'Connect MongoDB' : 'Change', _connectMongo, dark: cloud == null)),
            if (cloud != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _btn('Disconnect', () async {
                  final ok = await confirm(context, 'Disconnect MongoDB?', 'Existing backups stay in your database. This phone just stops using it.', verb: 'Disconnect');
                  if (!ok) return;
                  await CloudBackup.clear();
                  if (mounted) setState(() {});
                }),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  /// Backs up to MongoDB.
  Future<void> _cloudBackup() async {
    final cloud = CloudBackup.instance;
    if (_busy || cloud == null) return;
    setState(() {
      _busy = true;
      _restoreError = null;
    });
    try {
      final saved = await cloud.backUp(_s);
      if (!mounted) return;
      setState(() {
        _bytes = _s.dataBytes();
      });
      toast(context, 'Backed up to MongoDB · ${saved.clients} clients, ${saved.projects} projects, ${saved.docs} documents');
    } on CloudBackupException catch (e) {
      if (mounted) setState(() => _restoreError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Restores from MongoDB: pick the newest copy or the one before it.
  Future<void> _cloudRestore() async {
    final cloud = CloudBackup.instance;
    if (_busy || cloud == null) return;
    setState(() {
      _busy = true;
      _restoreError = null;
    });
    try {
      final versions = await cloud.versions();
      if (!mounted) return;
      if (versions.isEmpty) {
        setState(() => _restoreError = 'There is no backup in MongoDB yet. Use "Back up to MongoDB" first.');
        return;
      }
      final pick = await showModalBottomSheet<RemoteBackup>(
        context: context,
        backgroundColor: C.card,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Restore from MongoDB', style: display(20)),
              const SizedBox(height: 4),
              const Text('Choose which saved copy to restore.', style: TextStyle(color: C.muted, fontSize: 13)),
              const SizedBox(height: 10),
              for (final v in versions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.id == 'latest' ? 'Latest' : 'Previous', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${DateFormat('d MMM yyyy, HH:mm').format(v.savedAt)} · ${v.clients} clients, ${v.projects} projects, ${v.docs} documents · ${fmtBytes(v.bytes)}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(sheet, v),
                ),
            ]),
          ),
        ),
      );
      if (pick == null || !mounted) return;
      final ok = await confirm(
        context,
        'Replace all data?',
        'Restoring the ${pick.id == 'latest' ? 'latest' : 'previous'} copy from ${DateFormat('d MMM, HH:mm').format(pick.savedAt)} REPLACES every client, project, document and setting on this phone. '
            'This can\'t be undone. Back up first if you want to keep what is here now.',
        verb: 'Replace',
      );
      if (!ok || !mounted) return;
      final err = await _s.restoreJson(pick.json);
      if (!mounted) return;
      if (err != null) {
        setState(() => _restoreError = err);
        return;
      }
      _sync();
      setState(() {
        _bytes = _s.dataBytes();
      });
      toast(context, 'Restored ${_s.clients.length} clients, ${_s.projects.length} projects, ${_s.docs.length} documents');
    } on CloudBackupException catch (e) {
      if (mounted) setState(() => _restoreError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _restoreError = null;
    });
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Choose a Hustler backup (.json)');
      if (file == null || !mounted) return;
      final len = file.lengthSync() ?? await file.length() ?? 0;
      if (len > 64 * 1024 * 1024) {
        setState(() => _restoreError = 'That file is too large to be a Hustler backup.');
        return;
      }
      String text;
      try {
        text = utf8.decode(await file.readAsBytes());
      } catch (_) {
        setState(() => _restoreError = 'This is not a Hustler backup file.');
        return;
      }
      if (!mounted) return;
      final ok = await confirm(
        context,
        'Replace all data?',
        'Restoring "${file.name}" REPLACES every client, project, document and setting on this device with the contents of the file. '
            'This can\'t be undone. Back up first if you want to keep what is here now.',
        verb: 'Replace',
      );
      if (!ok || !mounted) return;
      final err = await _s.restoreJson(text);
      if (!mounted) return;
      if (err != null) {
        setState(() => _restoreError = err);
        toast(context, err);
        return;
      }
      _sync();
      setState(() {
        _bytes = _s.dataBytes();
      });
      toast(context, 'Restored ${_s.clients.length} clients, ${_s.projects.length} projects, ${_s.docs.length} documents');
    } catch (e) {
      if (mounted) setState(() => _restoreError = 'Could not open the file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final dl = context.watch<ModelDownloads>();
    var i = 0;
    final onDisk = aiModels.where(dl.isReady).fold(0.0, (a, m) => a + m.bytes);
    final active = Ai.current;
    final quick = s.profile.heuristicFallback || active == null;

    return Screen(
      title: 'Settings',
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          const Text('Your data and AI models live on this device only.', style: TextStyle(fontSize: 13, color: C.muted)).enter(i++),
          const SizedBox(height: 14),
          _summary(onDisk).enter(i++),
          const Section('Backup & restore'),
          _mongoCard().enter(i++),
          _backupCard().enter(i++),
          const Section('AI model manager'),
          const Text('Downloads keep going in the background, even if you leave this screen or close the app. A dropped connection resumes automatically, and paused or interrupted downloads continue where they stopped.',
              style: TextStyle(fontSize: 12, color: C.muted, height: 1.35)),
          if (_notifDenied) ...[
            const SizedBox(height: 8),
            _note(Icons.notifications_off_outlined, 'Notifications are off for Hustler. Downloads still run, but you will not see their progress outside the app.'),
          ],
          const SizedBox(height: 10),
          for (final m in aiModels) ...[
            _modelCard(context, dl, m, active?.id == m.id),
            const SizedBox(height: 10),
          ],
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 2),
            child: Text(
              quick ? 'Magic Scratchpad currently uses the quick parser.' : 'Magic Scratchpad currently uses ${active.name}.',
              style: const TextStyle(fontSize: 12, color: C.muted),
            ),
          ),
          _inference(),
          const Section('Business identity'),
          _identity().enter(i++),
          const Section('About'),
          CardContainer(
            radius: 18,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const HustlerLogo(size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hustler', style: display(17)),
                      const Text('Clients, projects, invoices and quotes for freelancers. No account, no cloud.',
                          style: TextStyle(fontSize: 12, color: C.muted, height: 1.35)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(double modelBytes) => CardContainer(
        color: C.dark,
        borderColor: C.dark,
        radius: 22,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text('DATA ON DEVICE', style: mono(10, color: C.dimLight, letterSpacing: 1.0))),
                  const SizedBox(height: 4),
                  FutureBuilder<int>(
                    future: _bytes,
                    builder: (_, snap) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(snap.hasData ? fmtBytes(snap.data!) : '…', style: display(26, color: C.textLight)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text('AI MODELS', style: mono(10, color: C.dimLight, letterSpacing: 1.0))),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(modelBytes == 0 ? 'None' : fmtBytes(modelBytes), style: display(26, color: C.textLight)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _note(IconData icon, String text, {Color bg = C.chipLight, Color fg = C.muted}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: fg, height: 1.35))),
          ],
        ),
      );

  Widget _backupCard() {
    final last = p.lastBackup;
    final days = last == null ? null : DateTime.now().difference(last).inDays;
    final cloud = CloudBackup.configured;
    return CardContainer(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (last == null)
            _note(Icons.warning_amber_rounded,
                cloud
                    ? 'Never backed up. Everything lives only on this phone, so a lost or reset phone means lost invoices. Back up to MongoDB now.'
                    : 'Never backed up. Everything lives only on this phone, so a lost or reset phone means lost invoices. Back up now and save the file somewhere safe.',
                bg: C.redLight, fg: C.redText)
          else ...[
            Text('LAST BACKUP', style: mono(10, color: C.muted, letterSpacing: .8)),
            const SizedBox(height: 3),
            Text('${DateFormat('d MMM yyyy, HH:mm').format(last)} · ${fmtBytes(p.lastBackupBytes)}', style: mono(13, color: C.text)),
            if (days != null && days >= 14) ...[
              const SizedBox(height: 8),
              _note(Icons.schedule_rounded, 'It has been $days days since your last backup.'),
            ],
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _btn(cloud ? 'Back up to MongoDB' : 'Back up now', cloud ? _cloudBackup : _backup, dark: true)),
              const SizedBox(width: 8),
              Expanded(child: _btn(cloud ? 'Restore from MongoDB' : 'Restore', cloud ? _cloudRestore : _restore)),
            ],
          ),
          if (cloud) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _btn('Export file', _backup)),
                const SizedBox(width: 8),
                Expanded(child: _btn('Import file', _restore)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text('Back up automatically every 5 minutes (and when I leave the app)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                Switch(
                  value: p.autoBackup,
                  activeThumbColor: Colors.white,
                  activeTrackColor: C.green,
                  onChanged: (v) {
                    _s.updateProfile((p) => p.autoBackup = v);
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
          if (_restoreError != null) ...[
            const SizedBox(height: 10),
            _note(Icons.error_outline_rounded, _restoreError!, bg: C.redLight, fg: C.redText),
          ],
          const SizedBox(height: 10),
          Text(
            cloud
                ? 'Backups keep the newest copy and the one before it. They travel over TLS but are stored as readable JSON in your database, so keep that database private. Restore replaces everything on this phone.'
                : 'Backup saves one .json file through the share sheet (Drive, email, Files). The file is not encrypted, so keep it private. Restore replaces everything on this device with the file you choose. Connect MongoDB above to back up to the cloud instead.',
            style: const TextStyle(fontSize: 11.5, color: C.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap, {bool dark = false}) => Pressable(
        onTap: _busy ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: dark ? C.dark : C.chipBg, borderRadius: BorderRadius.circular(13)),
          child: _busy
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: dark ? C.textLight : C.text))
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, style: TextStyle(color: dark ? C.textLight : C.text, fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
        ),
      );

  Widget _inference() => CardContainer(
        radius: 18,
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Inference hardware', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(
                        p.hardware == 'GPU' ? 'Prefer GPU, falls back to CPU if it fails' : 'CPU only. Slower but most compatible',
                        style: const TextStyle(fontSize: 12, color: C.muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: C.chipBg, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final hw in const ['GPU', 'CPU'])
                        Pressable(
                          onTap: () => _s.updateProfile((x) => x.hardware = hw),
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 52, minHeight: 44),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(color: p.hardware == hw ? C.dark : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                            child: Text(hw, style: mono(12, color: p.hardware == hw ? C.textLight : C.muted, weight: FontWeight.w600)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: C.borderLight),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Heuristic fallback', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                      SizedBox(height: 2),
                      Text('Skip the model and use the quick regex parser. Instant, but less accurate on messy notes.',
                          style: TextStyle(fontSize: 12, color: C.muted, height: 1.35)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: p.heuristicFallback,
                  activeThumbColor: Colors.white,
                  activeTrackColor: C.green,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: C.border,
                  onChanged: (v) {
                    _s.updateProfile((x) => x.heuristicFallback = v);
                    toast(context, v ? 'Quick parser on' : 'Language model on');
                  },
                ),
              ],
            ),
          ],
        ),
      );

  // ------------------------------------------------------------------ identity form

  Widget _field(
    String label,
    String key,
    void Function(Profile p, String v) apply, {
    String? Function(String v)? check,
    TextInputType? kb,
    int minLines = 1,
    int maxLines = 1,
    String? hint,
    TextCapitalization caps = TextCapitalization.none,
    List<TextInputFormatter>? formatters,
    TextInputAction? action,
  }) {
    final ctl = _c[key]!;
    final err = check?.call(ctl.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: mono(10, color: C.muted, letterSpacing: .8)),
          const SizedBox(height: 4),
          TextField(
            controller: ctl,
            keyboardType: kb ?? (maxLines > 1 ? TextInputType.multiline : null),
            textInputAction: action ?? (maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
            textCapitalization: caps,
            inputFormatters: formatters,
            minLines: minLines,
            maxLines: maxLines,
            onChanged: (v) {
              setState(() {});
              if (check?.call(v) == null) _s.updateProfile((x) => apply(x, v.trim()));
            },
            style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text),
            decoration: InputDecoration(
              hintText: hint,
              hintMaxLines: 6,
              hintStyle: const TextStyle(color: C.dim, fontSize: 14),
              errorText: err == null ? null : '$err (not saved yet)',
              errorMaxLines: 3,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: C.bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.dark, width: 1.5)),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.red)),
              focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.red, width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _identity() => CardContainer(
        radius: 18,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Printed on your invoices and quotes.', style: TextStyle(fontSize: 12, color: C.muted)),
            ),
            _field('Business name', 'biz', (x, v) => x.bizName = v, caps: TextCapitalization.words),
            _field('Your name', 'owner', (x, v) => x.ownerName = v, caps: TextCapitalization.words),
            _field('Email', 'email', (x, v) => x.email = v,
                kb: TextInputType.emailAddress,
                hint: 'name@company.com',
                check: (v) => v.trim().isEmpty || _emailRe.hasMatch(v.trim()) ? null : 'Enter a valid email'),
            _field('Phone', 'phone', (x, v) => x.phone = v,
                kb: TextInputType.phone,
                formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-().\s]'))],
                check: (v) => v.trim().isEmpty || v.replaceAll(RegExp(r'\D'), '').length >= 5 ? null : 'Enter a valid phone number'),
            _field('Address', 'address', (x, v) => x.address = v, minLines: 2, maxLines: 4, caps: TextCapitalization.sentences),
            _field('Tax ID', 'tax', (x, v) => x.taxId = v, caps: TextCapitalization.characters, hint: 'e.g. GST, VAT or EIN number'),
            _field('UPI id', 'upi', (x, v) => x.upi = v,
                hint: 'name@bank',
                check: (v) => v.trim().isEmpty || _upiRe.hasMatch(v.trim()) ? null : 'UPI ids look like name@bank'),
            _field('Bank details', 'bank', (x, v) => x.bank = v,
                minLines: 3,
                maxLines: 6,
                caps: TextCapitalization.sentences,
                hint: 'Account name\nBank and branch\nAccount number / IBAN\nIFSC / SWIFT'),
            _field('Default terms / notes', 'terms', (x, v) => x.terms = v,
                minLines: 2, maxLines: 5, caps: TextCapitalization.sentences, hint: 'Shown at the bottom of new documents'),
            Text('CURRENCY', style: mono(10, color: C.muted, letterSpacing: .8)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cur in const ['\$', '€', '£', '₹', '¥'])
                  Semantics(
                    button: true,
                    selected: p.currency == cur,
                    label: 'Currency $cur',
                    child: Pressable(
                      onTap: () => _s.updateProfile((x) => x.currency = cur),
                      child: Container(
                        width: 52,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: p.currency == cur ? C.dark : C.chipLight, borderRadius: BorderRadius.circular(12)),
                        child: Text(cur,
                            style: TextStyle(
                                fontFamily: 'Grotesk', fontSize: 17, color: p.currency == cur ? C.textLight : C.text, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field('Default tax %', 'defTax', (x, v) => x.defaultTax = double.tryParse(v.replaceAll(',', '.')) ?? 0,
                      kb: const TextInputType.numberWithOptions(decimal: true),
                      formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      check: (v) {
                        final n = double.tryParse(v.trim().replaceAll(',', '.'));
                        return v.trim().isEmpty || (n != null && n >= 0 && n <= 100) ? null : 'Enter 0 to 100';
                      }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field('Default due days', 'due', (x, v) => x.dueDays = int.tryParse(v) ?? 14,
                      kb: TextInputType.number,
                      action: TextInputAction.done,
                      formatters: [FilteringTextInputFormatter.digitsOnly],
                      check: (v) {
                        final n = int.tryParse(v.trim());
                        return n != null && n >= 0 && n <= 365 ? null : 'Enter 0 to 365 days';
                      }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _field('Hourly rate (${p.currency}), used by AI estimates', 'rate', (x, v) => x.hourlyRate = double.tryParse(v.replaceAll(',', '')) ?? 0,
                kb: const TextInputType.numberWithOptions(decimal: true),
                formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                check: (v) {
                  final n = double.tryParse(v.trim().replaceAll(',', ''));
                  return v.trim().isEmpty || (n != null && n >= 0) ? null : 'Enter a number, like 800';
                }),
          ],
        ),
      );

  // ------------------------------------------------------------------ model card

  String _eta(Duration d) => d.inSeconds <= 0 ? '' : (d.inMinutes > 0 ? '${d.inMinutes}m ${d.inSeconds % 60}s left' : '${d.inSeconds}s left');

  Widget _act(String label, VoidCallback onTap, {Color color = C.orange}) => Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      );

  Future<void> _use(AiModel m) async {
    if (!await confirm(context, 'Use ${m.name}?', 'Magic Scratchpad will read your notes with ${m.name} from now on. It loads the first time you use it.', verb: 'Use')) return;
    try {
      await Ai.use(m);
      if (mounted) toast(context, '${m.name} is now active');
    } catch (e) {
      if (mounted) toast(context, 'Could not switch model: $e');
    }
  }

  Future<void> _cancel(AiModel m, DlInfo d) async {
    if (d.progress > 0 && !await confirm(context, 'Cancel download?', 'Discard the ${fmtBytes(d.progress * m.bytes)} already downloaded of ${m.name}? You would start from zero next time.', verb: 'Discard')) return;
    await downloads.cancel(m);
  }

  Future<void> _remove(AiModel m, bool isActive) async {
    final others = aiModels.where((o) => o.id != m.id && downloads.isReady(o));
    final tail = !isActive
        ? ''
        : (others.isNotEmpty ? ' Hustler will switch to ${others.first.name}.' : ' Magic Scratchpad will use the quick parser until you download a model.');
    if (!await confirm(context, 'Remove ${m.name}?', 'Frees ${m.sizeLabel}. You can download it again any time.$tail', verb: 'Remove')) return;
    await Ai.remove(m);
  }

  Widget _modelCard(BuildContext context, ModelDownloads dl, AiModel m, bool isActive) {
    final d = dl.info(m);
    final ready = d.state == Dl.ready;
    final running = d.state == Dl.running;
    final line = switch (d.state) {
      Dl.ready => '${m.sizeLabel} · on this device',
      Dl.running => d.hold != null
          ? '${d.hold} · ${fmtBytes(d.progress * m.bytes)} of ${m.sizeLabel} saved'
          : [
              '${fmtBytes(d.progress * m.bytes)} of ${m.sizeLabel}',
              if (d.mbps > 0) '${d.mbps.toStringAsFixed(1)} MB/s',
              _eta(d.eta),
            ].where((x) => x.isNotEmpty).join(' · '),
      Dl.paused => 'Paused at ${(d.progress * 100).round()}% · ${fmtBytes(d.progress * m.bytes)} of ${m.sizeLabel} saved',
      Dl.failed => 'Interrupted at ${(d.progress * 100).round()}%${d.error == null ? '' : ' (${d.error})'}. Nothing is lost: resume continues where it stopped.',
      Dl.none => '${m.sizeLabel} download',
    };
    final pill = switch (d.state) {
      Dl.ready => isActive ? 'active' : 'ready',
      Dl.running => 'downloading',
      Dl.paused => 'review',
      Dl.failed => 'overdue',
      Dl.none => 'draft',
    };
    final pillText = switch (d.state) {
      Dl.running => d.hold != null ? 'Waiting ${(d.progress * 100).round()}%' : 'Downloading ${(d.progress * 100).round()}%',
      Dl.paused => 'Paused ${(d.progress * 100).round()}%',
      Dl.failed => 'Interrupted',
      Dl.none => 'Not installed',
      _ => null,
    };

    final bar = Container(color: ready ? C.green : C.orange);
    return CardContainer(
      radius: 18,
      padding: const EdgeInsets.all(14),
      borderColor: isActive ? C.green : C.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(m.blurb, style: const TextStyle(fontSize: 12, color: C.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Pill(pill, pillText),
            ],
          ),
          if (d.state != Dl.none) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Container(
                height: 7,
                color: C.draftBg,
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: ready ? 1.0 : d.progress),
                  duration: 500.ms,
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => FractionallySizedBox(
                    widthFactor: v.clamp(0.0, 1.0),
                    child: running ? bar.animate(onPlay: (c) => c.repeat()).shimmer(duration: 1100.ms, color: Colors.white54) : bar,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(line, style: mono(11, color: d.state == Dl.failed ? C.redText : C.muted), maxLines: 3, overflow: TextOverflow.ellipsis),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              children: [
                if (running)
                  _act('Pause', () => dl.pause(m))
                else if (d.state == Dl.paused || d.state == Dl.failed)
                  _act('Resume', () async {
                    await dl.resume(m);
                    _checkNotifications();
                  }),
                if (d.busy || d.state == Dl.failed)
                  _act('Cancel', () => _cancel(m, d), color: C.red)
                else if (!ready)
                  _act('Download', () async {
                    await dl.start(m);
                    _checkNotifications();
                  })
                else ...[
                  if (!isActive) _act('Use', () => _use(m)),
                  _act('Remove', () => _remove(m, isActive), color: C.muted),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String status;
  final String? text;
  const _Pill(this.status, this.text);

  @override
  Widget build(BuildContext context) {
    if (text == null) return StatusPill(status);
    final (bg, fg) = statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(text!, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}


/// Asks for the MongoDB connection string, tests it, and saves it only if it works. Pops the string on success.
class _MongoDialog extends StatefulWidget {
  const _MongoDialog();
  @override
  State<_MongoDialog> createState() => _MongoDialogState();
}

class _MongoDialogState extends State<_MongoDialog> {
  final ctl = TextEditingController();
  bool busy = false, show = false;
  String? error;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => ctl.text = d!.text!.trim());
  }

  Future<void> _save() async {
    final bad = CloudBackup.validate(ctl.text);
    if (bad != null) return setState(() => error = bad);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await CloudBackup.test(ctl.text);
      await CloudBackup.save(ctl.text);
      if (mounted) Navigator.pop(context, ctl.text.trim());
    } on CloudBackupException catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: C.border)),
        title: Text('Connect MongoDB', style: display(20)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Paste the connection string from MongoDB Atlas (Connect › Drivers). It is tested first, then kept in encrypted storage on this phone.',
                style: TextStyle(color: C.muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              enabled: !busy,
              obscureText: !show,
              minLines: 1,
              maxLines: show ? 4 : 1,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'mongodb+srv://user:password@cluster…',
                suffixIcon: IconButton(
                  tooltip: show ? 'Hide' : 'Show',
                  icon: Icon(show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => show = !show),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: busy ? null : _paste, icon: const Icon(Icons.content_paste_rounded, size: 18), label: const Text('Paste'))),
            if (error != null) Text(error!, style: const TextStyle(color: C.red, fontSize: 12.5, height: 1.35)),
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
          TextButton(
            onPressed: busy ? null : _save,
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.orange))
                : const Text('Test & save', style: TextStyle(color: C.orange, fontWeight: FontWeight.w700)),
          ),
        ],
      );
}
