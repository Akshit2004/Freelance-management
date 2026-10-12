import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' show ModelType;
import 'package:path_provider/path_provider.dart';

import 'log.dart';

class AiModel {
  final String id, name, blurb, url;
  final int bytes;
  final ModelType type;
  const AiModel(this.id, this.name, this.blurb, this.url, this.bytes, this.type);
  String get file => Uri.parse(url).pathSegments.last;
  String get sizeLabel => '${(bytes / 1e9).toStringAsFixed(1)} GB';
}

const aiModels = [
  AiModel('qwen3', 'Qwen 3 0.6B', 'Fastest · simple, clean notes',
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm', 614236160, ModelType.qwen3),
  AiModel('gemma4', 'Gemma 4 E2B', 'Smartest · slower, best for messy notes',
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm', 2588147712, ModelType.gemmaIt),
  AiModel('qwen25', 'Qwen 2.5 1.5B', 'Balanced speed and accuracy',
      'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      1597922856, ModelType.qwen),
];

enum Dl { none, running, paused, ready, failed }

/// Live state of one model download. Immutable snapshot; replaced on every change.
class DlInfo {
  final Dl state;
  final double progress; // 0..1
  final double mbps; // -1 = unknown
  final Duration eta;
  final String? error;
  final String? hold; // e.g. "Waiting for network": set while a download is retrying/paused by the system, not by the user
  const DlInfo(this.state, {this.progress = 0, this.mbps = -1, this.eta = Duration.zero, this.error, this.hold});
  bool get busy => state == Dl.running || state == Dl.paused;
}

/// App-wide model downloader. Lives outside every widget, so switching tabs or backgrounding the app never interrupts it:
/// the transfer runs in a native foreground service (notification + survives the app being swiped away),
/// split into parallel chunks for speed.
///
/// Interrupted downloads continue instead of restarting: every chunk is pausable, so the downloader keeps its partial data and
/// resumes it with an HTTP Range request (Hugging Face's CDN answers 206). A network drop only costs a retry delay (retries back off
/// up to ~8 min and don't count while offline; after the last retry the card offers Resume, and coming back to the app resumes by itself), a stalled connection is paused+resumed by a watchdog, and the user can pause/resume.
class ModelDownloads extends ChangeNotifier {
  static const group = 'hustler_models';
  static const chunks = 8; // parallel connections; HF's CDN scales well up to ~8
  static const retries = 10; // per chunk (the library's maximum); each retry RESUMES from the bytes already on disk
  final _info = <String, DlInfo>{};
  final _watchers = <String, List<VoidCallback>>{};
  late final String _dir;

  DlInfo info(AiModel m) => _info[m.id] ?? const DlInfo(Dl.none);
  bool isReady(AiModel m) => info(m).state == Dl.ready;
  String pathFor(AiModel m) => '$_dir/${m.file}';

  Future<void> init() async {
    _dir = (await getApplicationDocumentsDirectory()).path;
    final d = FileDownloader();
    // What is on disk is the truth about "installed", so look at it first and never let the downloader's own setup hide it.
    for (final m in aiModels) {
      if (await _complete(m)) _set(m, const DlInfo(Dl.ready));
    }
    try {
      await d.configure(androidConfig: [(Config.runInForeground, Config.always)]);
      d.configureNotificationForGroup(
        group,
        running: const TaskNotification('Hustler · {displayName}', 'Downloading on-device AI · {progress}'),
        complete: const TaskNotification('{displayName} is ready', 'Works fully offline now'),
        paused: const TaskNotification('{displayName} paused', 'Tap Resume to continue where it stopped'),
        error: const TaskNotification('Download interrupted', '{displayName} · open Hustler and tap Resume, nothing is lost'),
        progressBar: true,
      );
      await d.start(autoCleanDatabase: true); // also rehydrates transfers that survived an app restart
    } catch (e) {
      debugPrint('[Downloads] downloader setup failed: $e');
    }
    for (final m in aiModels) {
      if (isReady(m)) continue;
      final t = d.transfers.forId(_id(m));
      if (t != null && !_final(t.statusNotifier.value)) _watch(m, t);
    }
  }

  /// Re-checks disk; used by pull-to-refresh.
  Future<void> refresh() async {
    for (final m in aiModels) {
      if (info(m).busy) continue;
      if (await _complete(m)) {
        _set(m, const DlInfo(Dl.ready));
      } else if (info(m).state == Dl.failed && info(m).progress > 0) {
        unawaited(start(m)); // interrupted part-way (e.g. the connection was gone for a long time): continue it
      } else if (info(m).state != Dl.failed) {
        _set(m, const DlInfo(Dl.none));
      }
    }
  }

  String _id(AiModel m) => taskIdFor(m);
  static String taskIdFor(AiModel m) => 'model-${m.id}';

  /// The download as the library sees it. Public so a test can construct it (the library asserts on bad arguments).
  static ParallelDownloadTask buildTask(AiModel m) => ParallelDownloadTask(
        taskId: taskIdFor(m),
        url: m.url,
        filename: m.file,
        baseDirectory: BaseDirectory.applicationDocuments,
        group: group,
        displayName: m.name,
        chunks: chunks,
        retries: retries,
        allowPause: true, // required for resume: chunks keep partial data and continue with a Range request
        stallTimeout: const Duration(seconds: 60), // silent dead connection -> pause + resume
        requiresWiFi: false,
        updates: Updates.statusAndProgress,
      );
  bool _final(TaskStatus s) => s.isFinalState;

  /// Complete = file exists at (nearly) the expected size. The downloader only moves it into place once finished.
  Future<bool> _complete(AiModel m) async {
    final f = File(pathFor(m));
    return await f.exists() && await f.length() >= m.bytes * 0.99;
  }

  Future<void> start(AiModel m) async {
    if (isReady(m) || info(m).state == Dl.running) return;
    final d = FileDownloader();
    final existing = d.transfers.forId(_id(m));
    if (existing != null) {
      // paused, interrupted or stopped: continue it (the downloader resumes from the bytes it kept, or restarts if it kept none)
      _watch(m, existing);
      await existing.resume();
      return;
    }
    if (await d.permissions.status(PermissionType.notifications) != PermissionStatus.granted) {
      await d.permissions.request(PermissionType.notifications); // only needed to *show* the progress notification
    }
    _set(m, const DlInfo(Dl.running));
    try {
      Log.net('GET    ${Uri.parse(m.url).host}/…/${m.file}  ${m.sizeLabel}, $chunks connections  started');
      final t = await d.transfers.start(buildTask(m));
      _watch(m, t);
    } catch (e) {
      _set(m, DlInfo(Dl.failed, error: '$e'));
    }
  }

  final _loggedStatus = <String, TaskStatus>{};
  final _loggedStep = <String, int>{};

  /// Console lines for [Log.net]: status changes, and progress every 10%.
  void _logNet(AiModel m, TaskStatus s, double progress, double mbps) {
    if (_loggedStatus[m.id] != s) {
      _loggedStatus[m.id] = s;
      Log.net('GET    ${m.file}  ${s.name}${s == TaskStatus.complete ? '' : '  ${(progress * 100).round()}%'}');
    }
    final step = (progress * 10).floor();
    if (s == TaskStatus.running && step > (_loggedStep[m.id] ?? 0)) {
      _loggedStep[m.id] = step;
      Log.net('GET    ${m.file}  ${step * 10}%${mbps > 0 ? '  ${mbps.toStringAsFixed(1)} MB/s' : ''}');
    }
  }

  Future<void> pause(AiModel m) async {
    await FileDownloader().transfers.forId(_id(m))?.pause();
  }

  /// Continues a paused or interrupted download from where it stopped.
  Future<void> resume(AiModel m) => start(m);

  Future<void> cancel(AiModel m) async {
    await FileDownloader().cancelTaskWithId(_id(m));
    _set(m, const DlInfo(Dl.none));
  }

  Future<void> remove(AiModel m) async {
    final f = File(pathFor(m));
    if (await f.exists()) await f.delete();
    _set(m, const DlInfo(Dl.none));
  }

  void _watch(AiModel m, Transfer t) {
    for (final off in _watchers.remove(m.id) ?? <VoidCallback>[]) {
      off();
    }
    void sync() {
      final s = t.statusNotifier.value;
      _logNet(m, s, t.progressNotifier.value ?? 0, t.networkSpeedNotifier.value);
      if (s == TaskStatus.complete) {
        _complete(m).then((ok) => _set(m, ok ? const DlInfo(Dl.ready) : DlInfo(Dl.failed, error: 'File incomplete, tap to retry')));
      } else if (s == TaskStatus.failed || s == TaskStatus.notFound) {
        _set(m, DlInfo(Dl.failed, progress: (t.progressNotifier.value ?? 0).clamp(0.0, 1.0), error: 'Interrupted. Tap Resume to continue.'));
      } else if (s == TaskStatus.canceled) {
        _set(m, const DlInfo(Dl.none));
      } else {
        final hold = switch ((t.holdReasonNotifier.value, s)) {
          (TransferHoldReason.offline, _) => 'Waiting for network',
          (TransferHoldReason.waitingForWiFi, _) => 'Waiting for Wi-Fi',
          (_, TaskStatus.waitingToRetry) => 'Connection dropped, resuming…',
          _ => null,
        };
        _set(m, DlInfo(s == TaskStatus.paused ? Dl.paused : Dl.running,
            progress: (t.progressNotifier.value ?? 0).clamp(0.0, 1.0),
            mbps: hold == null ? t.networkSpeedNotifier.value : -1,
            eta: hold == null ? t.timeRemainingNotifier.value : Duration.zero,
            hold: hold));
      }
    }

    final ls = [t.statusNotifier, t.progressNotifier, t.networkSpeedNotifier, t.holdReasonNotifier];
    for (final l in ls) {
      l.addListener(sync);
    }
    _watchers[m.id] = [for (final l in ls) () => l.removeListener(sync)];
    sync();
  }

  void _set(AiModel m, DlInfo i) {
    _info[m.id] = i;
    notifyListeners();
  }
}

final downloads = ModelDownloads();
