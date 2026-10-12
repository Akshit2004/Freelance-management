import 'package:flutter_test/flutter_test.dart';
import 'package:freelance_os/magic.dart';
import 'package:freelance_os/voice.dart';

class FakeEngine implements SpeechEngine {
  bool initOk = true, permission = true;
  int listens = 0, stops = 0;
  late void Function(String) status;
  late void Function(String, bool) error;
  void Function(String, bool)? onResult;

  @override
  Future<bool> init({required void Function(String) onStatus, required void Function(String, bool) onError}) async {
    status = onStatus;
    error = onError;
    return initOk;
  }

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> listen({required List<String> phrases, required void Function(String, bool) onResult, required void Function(double) onLevel}) async {
    listens++;
    this.onResult = onResult;
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  group('normalizeSpoken', () {
    test('quantity first, hours, prices and tax', () {
      expect(normalizeSpoken('3 reels at 2000'), 'Reels 3x @ 2000');
      expect(normalizeSpoken('banner 3 at 1500'), 'Banner 3x @ 1500');
      expect(normalizeSpoken('8 hours of design at 85'), 'Design 8h @ 85');
      expect(normalizeSpoken('design 8 hours at 85'), 'Design 8h @ 85');
      expect(normalizeSpoken('logo design for 8000'), 'Logo design 8000');
      expect(normalizeSpoken('banner 2000 rupees'), 'Banner ₹2000');
      expect(normalizeSpoken('rupees 500 for the poster'), contains('₹500'));
      expect(normalizeSpoken('18 percent GST'), 'Tax 18%');
      expect(normalizeSpoken('10 percent off'), '10% off');
    });

    test('a streaming recognizer answers in capitals and spells numbers out', () {
      expect(normalizeSpoken('THREE REELS AT TWO THOUSAND RUPEES EACH'), 'Reels 3x @ ₹2000 each');
      expect(normalizeSpoken('LOGO DESIGN FOR EIGHT THOUSAND'), 'Logo design 8000');
      expect(normalizeSpoken('EIGHT HOURS OF EDITING AT EIGHTY FIVE'), 'Editing 8h @ 85');
      expect(normalizeSpoken('EIGHTEEN PERCENT GST'), 'Tax 18%');
      expect(normalizeSpoken('DUE IN SEVEN DAYS'), 'Due in 7 days');
      expect(normalizeSpoken('Logo designed 8 000'), 'Logo designed 8000');
    });

    test('new line commands split items', () {
      expect(normalizeSpoken('logo 8000 new line banner 1500 next item tax 18 percent'), 'Logo 8000\nBanner 1500\nTax 18%');
      expect(normalizeSpoken('   '), '');
    });

    test('spoken notes read correctly by the extractor', () {
      final spoken = normalizeSpoken(
          'THREE REELS AT TWO THOUSAND NEW LINE LOGO DESIGN FOR EIGHT THOUSAND NEW LINE EIGHT HOURS OF EDITING AT EIGHTY FIVE NEW LINE EIGHTEEN PERCENT GST NEW LINE DUE IN SEVEN DAYS');
      final p = parseNotes(spoken, const [], '₹');
      expect(p.items.map((i) => [i.desc.toLowerCase(), i.qty, i.rate]), [
        ['reels', 3, 2000],
        ['logo design', 1, 8000],
        ['editing', 8, 85],
      ]);
      expect(p.tax, 18);
      expect(p.terms, 'Net 7');
    });
  });

  group('VoiceController', () {
    test('streams partial then final text, keeps listening if the engine ends a session, and stops on request', () async {
      final e = FakeEngine();
      final v = VoiceController(engine: e, restartDelay: Duration.zero);
      final got = <(String, bool)>[];
      await v.start((t, f) => got.add((t, f)));
      expect(v.state, VoiceState.listening);
      expect(e.listens, 1);

      e.onResult!('3 reels at', false);
      e.onResult!('3 reels at 2000', true);
      expect(got, [('3 reels at', false), ('Reels 3x @ 2000', true)]);

      e.status('done');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(e.listens, 2);

      await v.stop();
      expect(v.state, VoiceState.idle);
      e.status('done');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(e.listens, 2, reason: 'no restart after stop');
      v.dispose();
    });

    test('repeated engine failures stop with a clear error; silence is not a failure', () async {
      final e = FakeEngine();
      final v = VoiceController(engine: e, restartDelay: Duration.zero);
      await v.start((_, _) {});
      e.error('error_no_match', false);
      expect(v.state, VoiceState.listening);
      expect(v.message, isNull);
      for (var i = 0; i < 3; i++) {
        e.error('error_audio', false);
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      expect(v.state, VoiceState.idle);
      expect(v.messageIsError, true);
      v.dispose();
    });

    test('missing microphone permission or model explains itself', () async {
      final denied = FakeEngine()
        ..initOk = false
        ..permission = false;
      final v1 = VoiceController(engine: denied);
      await v1.start((_, _) {});
      expect(v1.state, VoiceState.idle);
      expect(v1.message, contains('microphone'));
      v1.dispose();

      final noModel = FakeEngine()..initOk = false;
      final v2 = VoiceController(engine: noModel);
      await v2.start((_, _) {});
      expect(v2.message, contains('downloaded'));
      v2.dispose();
    });
  });
}
