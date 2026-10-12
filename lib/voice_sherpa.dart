import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'log.dart';
import 'voice.dart';
import 'voice_pack.dart';

const _sampleRate = 16000;

/// Offline streaming speech recognition (sherpa-onnx). The microphone is read continuously and decoded in a background isolate,
/// so there is no "session" to end: no restart gap, no beep, and nothing leaves the phone. An utterance is finished by 2 s of silence
/// (or 40 s of speech) and reported as final; while it is being spoken the text so far is reported as it grows.
class SherpaEngine implements SpeechEngine {
  SherpaEngine(this.pack);
  final VoicePack pack;

  final _recorder = AudioRecorder();
  Isolate? _isolate;
  SendPort? _worker;
  ReceivePort? _inbox;
  StreamSubscription<Uint8List>? _mic;
  void Function(String, bool)? _onResult;
  void Function(double)? _onLevel;

  @override
  Future<bool> init({required void Function(String status) onStatus, required void Function(String code, bool permanent) onError}) async =>
      pack.ready && await _recorder.hasPermission();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> listen({
    required List<String> phrases,
    required void Function(String words, bool isFinal) onResult,
    required void Function(double level) onLevel,
  }) async {
    _onResult = onResult;
    _onLevel = onLevel;
    if (_worker == null) await _spawn();
    if (_mic != null) return;
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
      autoGain: true,
      noiseSuppress: true,
      androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
    ));
    _mic = stream.listen((bytes) {
      _worker?.send(TransferableTypedData.fromList([bytes]));
      _onLevel?.call(_level(bytes));
    }, onError: (Object e) => Log.err('microphone: $e'));
  }

  /// RMS of the 16-bit samples, mapped so normal speech is about 0.3..0.8.
  static double _level(Uint8List b) {
    final d = ByteData.sublistView(b);
    final n = b.length ~/ 2;
    if (n == 0) return 0;
    var sum = 0.0;
    for (var i = 0; i < n; i += 4) {
      final v = d.getInt16(i * 2, Endian.little) / 32768.0;
      sum += v * v;
    }
    return (sqrt(sum / (n / 4)) * 5).clamp(0.0, 1.0);
  }

  Future<void> _spawn() async {
    final inbox = ReceivePort();
    _inbox = inbox;
    final ready = Completer<SendPort>();
    inbox.listen((m) {
      if (m is SendPort) {
        if (!ready.isCompleted) ready.complete(m);
      } else if (m is List && m.length == 2) {
        switch (m[0]) {
          case 'partial':
            _onResult?.call(m[1] as String, false);
          case 'final':
            _onResult?.call(m[1] as String, true);
          case 'error':
            Log.err('speech worker: ${m[1]}');
            if (!ready.isCompleted) ready.completeError(m[1] as String);
        }
      }
    });
    _isolate = await Isolate.spawn(_speechWorker, _Args(inbox.sendPort, pack.dir, [for (final f in VoicePack.files) f.name]), errorsAreFatal: false);
    _worker = await ready.future.timeout(const Duration(seconds: 30), onTimeout: () => throw StateError('the speech model did not load'));
  }

  @override
  Future<void> stop() async {
    await _mic?.cancel();
    _mic = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _worker?.send('flush'); // finishes the sentence being spoken and reports it
  }

  @override
  Future<void> cancel() async {
    await _mic?.cancel();
    _mic = null;
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await cancel();
    _worker?.send('exit');
    _worker = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _inbox?.close();
    _inbox = null;
    await _recorder.dispose();
  }
}

class _Args {
  final SendPort main;
  final String dir;
  final List<String> files; // encoder, decoder, joiner, tokens (same order as VoicePack.files)
  _Args(this.main, this.dir, this.files);
}

/// Runs in its own isolate: loads the model once, then turns audio chunks into text.
@pragma('vm:entry-point')
void _speechWorker(_Args a) {
  try {
    sherpa.initBindings();
    String f(int i) => '${a.dir}/${a.files[i]}';
    final recognizer = sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(encoder: f(0), decoder: f(1), joiner: f(2)),
        tokens: f(3),
        numThreads: 2,
        provider: 'cpu',
        debug: false,
        // modelType is left empty on purpose: the library reads it from the model's own metadata. Forcing the wrong type
        // ('zipformer' vs 'zipformer2') makes the native code abort, which closes the whole app.
      ),
      decodingMethod: 'greedy_search',
      enableEndpoint: true,
      rule1MinTrailingSilence: 3.0, // nothing said yet: keep waiting
      rule2MinTrailingSilence: 2.0, // after speech: 2 s of silence ends the sentence
      rule3MinUtteranceLength: 40,
    ));
    var stream = recognizer.createStream();
    var last = '';
    final inbox = ReceivePort();

    void drain({bool finish = false}) {
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final text = recognizer.getResult(stream).text.trim();
      if (finish || recognizer.isEndpoint(stream)) {
        if (text.isNotEmpty) a.main.send(['final', text]);
        recognizer.reset(stream);
        last = '';
      } else if (text != last) {
        last = text;
        a.main.send(['partial', text]);
      }
    }

    inbox.listen((m) {
      if (m is TransferableTypedData) {
        final bytes = m.materialize().asUint8List();
        final d = ByteData.sublistView(bytes);
        final n = bytes.length ~/ 2;
        final samples = Float32List(n);
        for (var i = 0; i < n; i++) {
          samples[i] = d.getInt16(i * 2, Endian.little) / 32768.0;
        }
        stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
        drain();
      } else if (m == 'flush') {
        stream.acceptWaveform(samples: Float32List(_sampleRate ~/ 2), sampleRate: _sampleRate); // half a second of silence
        stream.inputFinished();
        drain(finish: true);
        stream.free();
        stream = recognizer.createStream();
        last = '';
      } else if (m == 'exit') {
        stream.free();
        recognizer.free();
        inbox.close();
      }
    });
    a.main.send(inbox.sendPort);
  } catch (e) {
    a.main.send(['error', '$e']);
  }
}
