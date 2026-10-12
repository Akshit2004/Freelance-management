import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freelance_os/downloads.dart';

void main() {
  test('every model builds a download task the library accepts (it asserts on bad arguments, e.g. retries outside 1..10)', () {
    for (final m in aiModels) {
      late ParallelDownloadTask t;
      expect(() => t = ModelDownloads.buildTask(m), returnsNormally, reason: m.name);
      expect(t.retries, inInclusiveRange(1, 10));
      expect(t.chunks, inInclusiveRange(2, 16));
      expect(t.allowPause, true, reason: 'resume needs pausable chunks');
      expect(t.filename, m.file);
      expect(t.taskId, ModelDownloads.taskIdFor(m));
    }
  });

  test('model catalogue is sane', () {
    expect(aiModels.map((m) => m.id).toSet().length, aiModels.length, reason: 'unique ids');
    expect(aiModels.map((m) => m.file).toSet().length, aiModels.length, reason: 'unique file names');
    for (final m in aiModels) {
      expect(m.url, startsWith('https://huggingface.co/'));
      expect(m.bytes, greaterThan(100 * 1000 * 1000));
      expect(m.file, endsWith('.litertlm'));
    }
  });
}
