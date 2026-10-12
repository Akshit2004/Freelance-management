import 'package:flutter/material.dart';
import 'package:freelance_os/magic.dart';
import 'package:freelance_os/voice.dart';

import 'harness.dart';
import 'voice_test.dart' show FakeEngine;

TextField _pad(WidgetTester t) => t.widget<TextField>(find.byKey(const Key('magic-pad')));

void main() {
  testWidgets('tapping the mic dictates one line per utterance into the pad, then stops cleanly', (t) async {
    resetStore();
    final e = FakeEngine();
    final v = VoiceController(engine: e, restartDelay: Duration.zero);
    await pumpScreen(t, MagicPage(voice: v));

    await t.tap(find.byIcon(Icons.mic_rounded));
    await settle(t);
    expect(v.state, VoiceState.listening);
    expect(find.textContaining('LISTENING'), findsOneWidget);
    expect(_pad(t).readOnly, true, reason: 'the pad is locked while the mic writes to it');

    e.onResult!('3 reels at 2000', true);
    await t.pump();
    expect(_pad(t).controller!.text, 'Reels 3x @ 2000\n');

    e.onResult!('logo design for 8000', false);
    await t.pump();
    expect(_pad(t).controller!.text, 'Reels 3x @ 2000\nLogo design 8000');

    await t.tap(find.byIcon(Icons.stop_rounded));
    await settle(t);
    expect(v.state, VoiceState.idle);
    expect(_pad(t).readOnly, false);
    expect(_pad(t).controller!.text, 'Reels 3x @ 2000\nLogo design 8000', reason: 'trailing blank line trimmed');
    expect(find.textContaining('2 LINES'), findsWidgets, reason: 'the extractor read both dictated lines');
    expect(t.takeException(), isNull);
  });

  testWidgets('dictation continues from what is already typed', (t) async {
    resetStore();
    final e = FakeEngine();
    final v = VoiceController(engine: e, restartDelay: Duration.zero);
    await pumpScreen(t, MagicPage(voice: v));
    await t.enterText(find.byKey(const Key('magic-pad')), 'Acme - Website');
    await t.tap(find.byIcon(Icons.mic_rounded));
    await settle(t);
    e.onResult!('banner 1500', true);
    await t.pump();
    expect(_pad(t).controller!.text, 'Acme - Website\nBanner 1500\n');
    await v.stop();
    await settle(t);
  });

  testWidgets('no microphone permission: says how to fix it instead of failing silently', (t) async {
    resetStore();
    final e = FakeEngine()
      ..initOk = false
      ..permission = false;
    final v = VoiceController(engine: e);
    await pumpScreen(t, MagicPage(voice: v));
    await t.tap(find.byIcon(Icons.mic_rounded));
    await settle(t);
    expect(find.textContaining('needs the microphone'), findsOneWidget);
    expect(_pad(t).readOnly, false);
  });

  for (final (size, scale) in [(const Size(320, 568), 1.5), (const Size(360, 800), 1.0)]) {
    testWidgets('mic button and listening status do not overflow at $size x$scale', (t) async {
      resetStore();
      final e = FakeEngine();
      final v = VoiceController(engine: e, restartDelay: Duration.zero);
      await pumpScreen(t, MagicPage(voice: v), size: size, textScale: scale);
      await t.tap(find.byIcon(Icons.mic_rounded));
      await settle(t);
      e.onResult!('3 reels at 2000 new line logo design for 8000 new line 18 percent GST', false);
      await t.pump();
      expect(t.takeException(), isNull);
      await v.stop();
      await settle(t);
    });
  }
}
