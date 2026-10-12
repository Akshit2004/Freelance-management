import 'package:flutter_test/flutter_test.dart';
import 'package:freelance_os/ai.dart';
import 'package:freelance_os/magic.dart';

void main() {
  test('cleanPad strips thinking blocks, fences, bullets and echoes', () {
    expect(cleanPad('<think>\nhmm\n</think>\nAcme - Site\n- Logo 1x @ 8000\n```\ntax 18%, net 7'), 'Acme - Site\nLogo 1x @ 8000\ntax 18%, net 7');
    expect(cleanPad('<think>still thinking'), '', reason: 'an unfinished think block shows nothing yet');
    expect(cleanPad('Notes: x\nReel 3x @ 2000'), 'Reel 3x @ 2000');
  });

  test('completeLines hides the line still being written', () {
    expect(completeLines('Reel 3x @ 2000\nLogo 1x @ 8'), 'Reel 3x @ 2000');
    expect(completeLines('Reel 3x @ 15'), '');
    expect(completeLines('A\nB\n'), 'A\nB');
  });

  test('the format the prompt asks the model for is exactly what the extractor reads', () {
    const out = 'Sharma - Reels\nReel 3x @ 2000\nLogo 1x @ 8000\nDev work 8h @ 85\ntax 18%, net 7, 10% off';
    final p = parseNotes(cleanPad(out), const [], '₹');
    expect(p.items.map((i) => [i.desc, i.qty, i.rate]), [
      ['Reel', 3, 2000],
      ['Logo', 1, 8000],
      ['Dev work', 8, 85],
    ]);
    expect(p.tax, 18);
    expect(p.terms, 'Net 7');
    expect(p.discountPct, 10);
  });

  test('stats summary reads like a human wrote it', () {
    const s = AiStats(load: Duration(seconds: 4), firstToken: Duration(milliseconds: 900), total: Duration(milliseconds: 3900), tokens: 31);
    expect(s.tokensPerSecond, closeTo(10, .01));
    expect(s.summary, '0.9s to first word · 10 tok/s · model loaded in 4.0s');
  });
}
