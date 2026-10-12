import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'log.dart';

class VoiceFile {
  final String name;
  final int bytes;
  const VoiceFile(this.name, this.bytes);
  String get url => '${VoicePack.base}/$name';
}

enum VoiceState2 { none, downloading, ready, failed }

/// The offline speech model behind voice typing (a streaming English recognizer, about 73 MB, downloaded once).
/// Four small files in `<app documents>/voice`; "ready" means every file is on disk at its exact size.
class VoicePack extends ChangeNotifier {
  static const base = 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26/resolve/main';
  static const files = [
    VoiceFile('encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx', 71083163),
    VoiceFile('decoder-epoch-99-avg-1-chunk-16-left-128.onnx', 2092621),
    VoiceFile('joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx', 259335),
    VoiceFile('tokens.txt', 5048),
  ];
  static final totalBytes = files.fold<int>(0, (s, f) => s + f.bytes);
  static String sizeLabel() => '${(totalBytes / 1e6).round()} MB';

  VoiceState2 state = VoiceState2.none;
  double progress = 0; // 0..1 across all files
  String? error;
  late String dir;
  final _transfers = <String, Transfer>{};
  final _progress = <String, double>{};

  bool get ready => state == VoiceState2.ready;
  bool get busy => state == VoiceState2.downloading;
  String path(VoiceFile f) => '$dir/${f.name}';

  /// True when every file of the pack exists in [dir] at its exact size.
  static Future<bool> isComplete(String dir) async {
    for (final f in files) {
      final file = File('$dir/${f.name}');
      if (!await file.exists() || await file.length() != f.bytes) return false;
    }
    return true;
  }

  Future<void> init() async {
    dir = '${(await getApplicationDocumentsDirectory()).path}/voice';
    if (await isComplete(dir)) {
      state = VoiceState2.ready;
      notifyListeners();
    }
  }

  Future<void> download() async {
    if (ready || busy) return;
    state = VoiceState2.downloading;
    progress = 0;
    error = null;
    _progress.clear();
    notifyListeners();
    final started = DateTime.now();
    Log.net('GET    voice pack  ${files.length} files, ${sizeLabel()}  started');
    try {
      await Directory(dir).create(recursive: true);
      final d = FileDownloader();
      final all = <Future<void>>[];
      for (final f in files) {
        if (File(path(f)).existsSync() && File(path(f)).lengthSync() == f.bytes) {
          _progress[f.name] = 1;
          continue;
        }
        final task = f.bytes > 20e6
            ? ParallelDownloadTask(
                taskId: 'voice-${f.name}',
                url: f.url,
                filename: f.name,
                directory: 'voice',
                baseDirectory: BaseDirectory.applicationDocuments,
                chunks: 6,
                retries: 5,
                allowPause: true,
                updates: Updates.statusAndProgress)
            : DownloadTask(
                taskId: 'voice-${f.name}',
                url: f.url,
                filename: f.name,
                directory: 'voice',
                baseDirectory: BaseDirectory.applicationDocuments,
                retries: 5,
                allowPause: true,
                updates: Updates.statusAndProgress);
        final t = await d.transfers.start(task);
        _transfers[f.name] = t;
        t.progressNotifier.addListener(() {
          _progress[f.name] = t.progressNotifier.value ?? 0;
          _recompute();
        });
        all.add(t.result.then((r) {
          if (r.status != TaskStatus.complete) throw TaskException('${f.name}: ${r.status.name}');
        }));
      }
      await Future.wait(all);
      if (!await isComplete(dir)) throw StateError('a downloaded file has the wrong size');
      state = VoiceState2.ready;
      progress = 1;
      Log.net('GET    voice pack  complete  ${DateTime.now().difference(started).inSeconds}s');
    } catch (e) {
      state = VoiceState2.failed;
      error = 'Download failed: ${e is TaskException ? e.description : e}';
      Log.net('GET    voice pack  FAILED  $e');
    }
    notifyListeners();
  }

  void _recompute() {
    final done = files.fold<double>(0, (s, f) => s + (_progress[f.name] ?? 0) * f.bytes);
    progress = (done / totalBytes).clamp(0.0, 1.0);
    notifyListeners();
  }

  Future<void> cancel() async {
    for (final f in files) {
      await FileDownloader().cancelTaskWithId('voice-${f.name}');
    }
    _transfers.clear();
    state = VoiceState2.none;
    notifyListeners();
  }

  Future<void> remove() async {
    final d = Directory(dir);
    if (await d.exists()) await d.delete(recursive: true);
    state = VoiceState2.none;
    progress = 0;
    notifyListeners();
  }
}

final voicePack = VoicePack();
