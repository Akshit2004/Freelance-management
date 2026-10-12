import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freelance_os/voice_pack.dart';

void main() {
  test('the pack counts as installed only when every file is there at its exact size', () async {
    final dir = await Directory.systemTemp.createTemp('voicepack');
    addTearDown(() => dir.delete(recursive: true));
    expect(await VoicePack.isComplete(dir.path), false);
    for (final f in VoicePack.files) {
      await File('${dir.path}/${f.name}').writeAsBytes(List.filled(f.bytes, 1));
    }
    expect(await VoicePack.isComplete(dir.path), true);
    await File('${dir.path}/${VoicePack.files.last.name}').writeAsBytes([1, 2, 3]);
    expect(await VoicePack.isComplete(dir.path), false, reason: 'a truncated file must not count');
  });

  test('pack catalogue is sane', () {
    expect(VoicePack.files.length, 4);
    expect(VoicePack.totalBytes, greaterThan(70 * 1000 * 1000));
    for (final f in VoicePack.files) {
      expect(f.url, startsWith('https://huggingface.co/'));
    }
    expect(VoicePack.sizeLabel(), '73 MB');
  });
}
