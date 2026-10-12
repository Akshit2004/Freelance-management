import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'downloads.dart';
import 'models.dart';
import 'ui.dart';

/// GSAP-style timeline: one controller is the clock, every tween is placed on it by start/end second.
/// `tl.t(1.2, 1.8, Curves.easeOutBack)` is 0 before 1.2s, 1 after 1.8s, eased in between.
class Tl {
  final AnimationController c;
  final double seconds;
  const Tl(this.c, this.seconds);
  double get now => c.value * seconds;
  double t(double from, double to, [Curve curve = Curves.linear]) => curve.transform(((now - from) / (to - from)).clamp(0.0, 1.0));
}

/// The Hustler mark as vector paths: an H whose crossbar is a rising revenue line and whose right leg is an arrow.
/// [draw] traces the strokes like an SVG stroke-dashoffset animation, [badge] pops the orange squircle behind it.
class LogoPainter extends CustomPainter {
  final double draw, badge;
  final Color ink;
  LogoPainter({this.draw = 1, this.badge = 0, this.ink = C.orange});

  static final _paths = [
    Path()..moveTo(22, 22)..lineTo(22, 78),
    Path()..moveTo(22, 66)..lineTo(38, 52)..lineTo(51, 60)..lineTo(68, 42),
    Path()..moveTo(68, 78)..lineTo(68, 22),
    Path()..moveTo(58, 32)..lineTo(68, 22)..lineTo(78, 32),
  ];
  static final _metrics = [for (final p in _paths) p.computeMetrics().first];
  static final _total = _metrics.fold(0.0, (s, m) => s + m.length);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    if (badge > 0) {
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(50, 50), width: 96 * badge, height: 96 * badge), Radius.circular(28 * badge));
      canvas.drawRRect(r.shift(const Offset(0, 5)),
          Paint()..color = C.orange.withValues(alpha: .4 * badge.clamp(0, 1))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
      canvas.drawRRect(
          r,
          Paint()
            ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF8A4C), C.orange, C.orangeDark])
                .createShader(const Rect.fromLTWH(2, 2, 96, 96)));
    }
    final color = Color.lerp(ink, C.textLight, badge.clamp(0, 1))!;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    var left = draw.clamp(0.0, 1.0) * _total;
    Offset? head;
    for (final m in _metrics) {
      if (left <= 0) break;
      final take = min(left, m.length);
      canvas.drawPath(m.extractPath(0, take), stroke);
      head = m.getTangentForOffset(take)?.position;
      left -= take;
    }
    if (head != null && draw < 1) {
      // glowing pen tip riding the line
      canvas.drawCircle(head, 9, Paint()..color = C.orange.withValues(alpha: .5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(head, 4.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(LogoPainter o) => o.draw != draw || o.badge != badge || o.ink != ink;
}

class HustlerLogo extends StatelessWidget {
  final double size, draw, badge;
  final Color ink;
  const HustlerLogo({super.key, this.size = 40, this.draw = 1, this.badge = 1, this.ink = C.orange});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: LogoPainter(draw: draw, badge: badge, ink: ink));
}

/// GSAP SplitText: each character springs up from below with a blur, staggered.
/// Words stay together when it wraps; a word wider than the line shrinks to fit. Right-to-left / joined scripts (Arabic, Hebrew ...)
/// can't be split per letter without breaking their shapes, so those and reduced-motion get a plain (faded) Text.
class SplitText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int delayMs, staggerMs;
  const SplitText(this.text, {super.key, required this.style, this.delayMs = 0, this.staggerMs = 26});

  static final _joined = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF\u0900-\u0DFF]');
  static const _maxAnimated = 60; // beyond this a per-letter animation is just cost

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final reduce = MediaQuery.disableAnimationsOf(context);
    final plain = Text(text, style: style);
    if (reduce) return plain;
    if (_joined.hasMatch(text) || text.characters.length > _maxAnimated) {
      return plain.animate(delay: delayMs.ms).fadeIn(duration: 380.ms).slideY(begin: .3, end: 0, duration: 520.ms, curve: Curves.easeOutCubic);
    }
    var i = 0;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Wrap(
        children: [
          for (final word in text.split(' '))
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final ch in '$word '.characters)
                  Text(ch, style: style)
                      .animate(delay: (delayMs + i++ * staggerMs).ms)
                      .fadeIn(duration: 260.ms)
                      .slideY(begin: .7, end: 0, duration: 520.ms, curve: Curves.easeOutBack)
                      .blur(begin: const Offset(0, 6), end: Offset.zero, duration: 360.ms),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Number that rolls up to its value, and re-rolls whenever the value changes.
class CountUp extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle? style;
  const CountUp(this.value, {super.key, required this.format, this.style});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.isFinite ? value : 0),
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : 1100.ms,
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(format(v), style: style),
      );
}

/// Checkmark that draws itself (SVG path trim) when [on] flips to true and un-draws when it flips back.
class DrawCheck extends StatelessWidget {
  final bool on;
  final double size;
  final Color color;
  const DrawCheck({super.key, required this.on, this.size = 14, this.color = Colors.white});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: on ? 1 : 0), // begin == end on first build: items that load already ticked don't animate
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : 340.ms,
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => CustomPaint(size: Size.square(size), painter: _CheckPainter(v, color)),
      );
}

class _CheckPainter extends CustomPainter {
  final double t;
  final Color color;
  _CheckPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final p = Path()
      ..moveTo(size.width * .14, size.height * .54)
      ..lineTo(size.width * .40, size.height * .78)
      ..lineTo(size.width * .86, size.height * .24);
    final m = p.computeMetrics().first;
    canvas.drawPath(
        m.extractPath(0, m.length * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .16
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_CheckPainter o) => o.t != t || o.color != color;
}

/// Drop-in for a tab's `ListView`: pull down to reload from disk. The Hustler mark draws itself as you pull, then spins while it reloads.
class RefreshListView extends StatefulWidget {
  final EdgeInsets? padding;
  final List<Widget> children;
  const RefreshListView({super.key, this.padding, required this.children});
  @override
  State<RefreshListView> createState() => _RefreshListViewState();
}

class _RefreshListViewState extends State<RefreshListView> {
  double pull = 0;
  bool refreshing = false;

  Future<void> _run() async {
    HapticFeedback.mediumImpact();
    setState(() => refreshing = true);
    try {
      // a failing reload must never leave the spinner stuck: each leg swallows its own error
      await Future.wait([
        store.reload().catchError((Object _) {}),
        downloads.refresh().catchError((Object _) {}),
        Future<void>.delayed(900.ms),
      ]).timeout(const Duration(seconds: 8)); // and a hung disk read can't pin the spinner either
    } catch (_) {
      // the data on screen simply stays as it was
    } finally {
      if (mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          refreshing = false;
          pull = 0;
        });
      }
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (refreshing || n.depth != 0) return false; // ignore nested scrollables (carousels inside a card)
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      setState(() => pull = (pull - n.overscroll).clamp(0, 160));
    } else if (n is ScrollEndNotification || (n is ScrollUpdateNotification && n.metrics.pixels > 0 && pull > 0)) {
      if (pull > 0) setState(() => pull = 0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final k = refreshing ? 1.0 : (pull / 90).clamp(0.0, 1.0);
    return Stack(children: [
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: RefreshIndicator(
          color: Colors.transparent,
          backgroundColor: Colors.transparent,
          elevation: 0,
          strokeWidth: .01,
          displacement: 70,
          onRefresh: _run,
          // while reloading, the content slides down so the spinner never sits on top of the first item
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: refreshing ? 56.0 : 0.0),
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : 250.ms,
            curve: Curves.easeOutCubic,
            builder: (_, extra, _) {
              final pad = widget.padding ?? EdgeInsets.zero;
              return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: pad.copyWith(top: pad.top + extra), children: widget.children);
            },
          ),
        ),
      ),
      Positioned(
        top: -56 + 72 * k,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Opacity(
            opacity: k,
            child: Center(
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: C.dark,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: C.orange.withValues(alpha: .35 * k), blurRadius: 18, spreadRadius: 1)],
                ),
                child: refreshing
                    ? const HustlerLogo(size: 28, badge: 0)
                        .animate(onPlay: (c) => c.repeat())
                        .rotate(duration: 900.ms, curve: Curves.easeInOutCubic)
                    : Transform.rotate(angle: k * pi, child: HustlerLogo(size: 28, draw: k, badge: 0)),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Slow-drifting vector shapes behind every screen: rings, plus signs and dots, plus two soft colour washes.
class Backdrop extends StatefulWidget {
  const Backdrop({super.key});
  @override
  State<Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<Backdrop> with SingleTickerProviderStateMixin {
  // The drift is slow, so it's repainted at ~30fps instead of every frame (half the GPU/battery cost, same look).
  // The ticker is muted by TickerMode whenever the route is covered / off-screen, and Flutter stops frames in the background.
  final phase = ValueNotifier<double>(0);
  late final _ticker = createTicker((e) {
    if ((e - _last).inMilliseconds < 33) return;
    _last = e;
    phase.value = (e.inMilliseconds % 40000) / 40000 * 2 * pi;
  });
  Duration _last = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context); // reduced motion: draw once, never tick
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        const RepaintBoundary(child: CustomPaint(painter: _WashPainter())), // static colour washes, painted once
        RepaintBoundary(child: CustomPaint(painter: _BackdropPainter(phase))),
      ]);
}

class _WashPainter extends CustomPainter {
  const _WashPainter();
  @override
  void paint(Canvas canvas, Size size) {
    for (final (cx, cy, color) in [(0.0, 0.0, C.orange), (1.0, 1.0, C.amber)]) {
      final center = Offset(size.width * cx, size.height * cy);
      final r = size.width * .8;
      canvas.drawCircle(center, r, Paint()..shader = RadialGradient(colors: [color.withValues(alpha: .10), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: center, radius: r)));
    }
  }

  @override
  bool shouldRepaint(_WashPainter o) => false;
}

class _BackdropPainter extends CustomPainter {
  final ValueListenable<double> phase;
  _BackdropPainter(this.phase) : super(repaint: phase);

  // x, y (0..1), size, speed, phase, kind(0 ring, 1 plus, 2 dot), colour
  static const shapes = [
    (.12, .10, 34.0, 1.0, 0.0, 0, C.orange),
    (.88, .18, 22.0, 2.0, 1.3, 1, C.blue),
    (.74, .36, 46.0, 1.0, 2.6, 0, C.green),
    (.10, .52, 18.0, 3.0, 4.0, 2, C.orange),
    (.90, .66, 26.0, 2.0, 0.7, 1, C.amber),
    (.20, .80, 40.0, 1.0, 3.3, 0, C.blue),
    (.80, .92, 16.0, 3.0, 5.1, 2, C.orange),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final (x, y, s, speed, phase, kind, color) in shapes) {
      final a = t * speed + phase;
      final o = Offset(size.width * x + sin(a) * 16, size.height * y + cos(a * .8) * 22);
      final paint = line..color = color.withValues(alpha: .16);
      switch (kind) {
        case 0:
          canvas.drawCircle(o, s, paint);
          canvas.drawArc(Rect.fromCircle(center: o, radius: s * .55), a * 2, pi * 1.2, false, paint);
        case 1:
          canvas.save();
          canvas.translate(o.dx, o.dy);
          canvas.rotate(a);
          canvas.drawLine(Offset(-s / 2, 0), Offset(s / 2, 0), paint);
          canvas.drawLine(Offset(0, -s / 2), Offset(0, s / 2), paint);
          canvas.restore();
        default:
          canvas.drawCircle(o, s / 3, Paint()..color = color.withValues(alpha: .22));
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter o) => o.phase != phase;
}
