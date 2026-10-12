import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'ui.dart';

/// Launch animation, one GSAP-style timeline (seconds):
///  0.0 rings sweep on · 0.2 logo strokes trace · 1.4 badge pops + shockwave + sparks · 1.7 wordmark springs in
///  2.4 underline + tagline · 3.0 circular reveal into the app. Tap anywhere to skip to the reveal.
class IntroOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const IntroOverlay({super.key, required this.onDone});
  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay> with SingleTickerProviderStateMixin {
  static const secs = 3.8;
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3800));
  late final tl = Tl(c, secs);
  bool popped = false, done = false, started = false;

  @override
  void initState() {
    super.initState();
    c.addListener(() {
      if (!popped && tl.now > 1.4) {
        popped = true;
        HapticFeedback.heavyImpact();
      }
    });
    // Status listener, not `forward().whenComplete`: skipping re-targets the controller with animateTo, which cancels the
    // forward() future, so onDone would never fire and the opaque overlay would swallow every tap for good.
    c.addStatusListener((st) {
      if (st == AnimationStatus.completed && !done) {
        setState(() => done = true); // IgnorePointer flips even if the parent keeps us mounted
        widget.onDone();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) return;
    started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // reduced motion: no pyrotechnics, just a short fade out of the finished frame
      popped = true; // no haptic thump either
      c.value = 3.0 / secs;
      c.animateTo(1, duration: const Duration(milliseconds: 350));
    } else {
      c.forward();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _skip() {
    if (tl.now < 3.0) c.animateTo(1, duration: const Duration(milliseconds: 650), curve: Curves.easeInCubic);
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: done, // never block the app once the intro has finished
        // a brand splash, not content: it ignores the system font scale so the wordmark can't outgrow the screen
        child: MediaQuery.withNoTextScaling(child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light, systemNavigationBarIconBrightness: Brightness.light),
        child: Material(
          type: MaterialType.transparency, // overlay sits above the Navigator; without a Material, Text gets the debug underline
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          child: LayoutBuilder(
            builder: (_, box) {
              final size = box.biggest;
              final center = Offset(size.width / 2, size.height * .40);
              // everything scales with the screen; the height term keeps logo + wordmark + tagline (about 640 units tall) inside short/landscape screens
              final unit = min(size.shortestSide / 390, size.height / 640);
              return AnimatedBuilder(
                animation: c,
                builder: (_, _) {
                  final reveal = tl.t(3.0, 3.8, Curves.easeInOutCubic);
                  final logo = 150 * unit;
                  return ClipPath(
                    clipper: _Hole(center, reveal * sqrt(size.width * size.width + size.height * size.height)),
                    child: Container(
                      color: C.dark,
                      child: Stack(children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _Fx(
                              center: center,
                              unit: unit,
                              rings: tl.t(0, 1.3, Curves.easeOutCubic),
                              spin: tl.now * .5,
                              shock: tl.t(1.4, 2.3, Curves.easeOutCubic),
                              burst: tl.t(1.4, 2.0, Curves.easeOutCubic),
                              fade: 1 - tl.t(2.6, 3.0),
                            ),
                          ),
                        ),
                        Positioned(
                          left: center.dx - logo / 2,
                          top: center.dy - logo / 2,
                          child: Transform.scale(
                            scale: 1 + .06 * sin(tl.t(1.4, 2.4) * pi) + reveal * .6,
                            child: Opacity(
                              opacity: 1 - reveal,
                              child: HustlerLogo(size: logo, draw: tl.t(.2, 1.4, Curves.easeInOutCubic), badge: tl.t(1.35, 2.0, Curves.elasticOut)),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: center.dy + logo * .72,
                          child: Opacity(opacity: 1 - reveal, child: _wordmark(unit)),
                        ),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        ),
      )));

  Widget _wordmark(double unit) {
    final line = tl.t(2.4, 2.9, Curves.easeOutCubic);
    final tag = tl.t(2.5, 3.0, Curves.easeOutCubic);
    return Column(children: [
      FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (i, ch) in 'HUSTLER'.split('').indexed)
          Builder(builder: (_) {
            final from = 1.7 + i * .07;
            final s = tl.t(from, from + .6, Curves.easeOutBack);
            final blur = (1 - tl.t(from, from + .35)) * 8;
            Widget t = Text(ch, style: TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 40 * unit, letterSpacing: 5 * unit, color: C.textLight));
            if (blur > .2) t = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 0, sigmaY: blur), child: t);
            return Opacity(opacity: tl.t(from, from + .3), child: Transform.translate(offset: Offset(0, (1 - s) * 36 * unit), child: t));
          }),
      ])),
      SizedBox(height: 12 * unit),
      Container(width: 150 * unit * line, height: 3, decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(2))),
      SizedBox(height: 14 * unit),
      Opacity(
        opacity: tag,
        child: FittedBox(
          fit: BoxFit.scaleDown, // the tagline starts widely tracked: scale it instead of letting it wrap
          child: Text('FREELANCE OS · RUNS OFFLINE', maxLines: 1, style: mono(11 * unit, color: C.dimLight, letterSpacing: (12 - 9 * tag) * unit, weight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

class _Hole extends CustomClipper<Path> {
  final Offset center;
  final double r;
  _Hole(this.center, this.r);
  @override
  Path getClip(Size size) =>
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addOval(Rect.fromCircle(center: center, radius: r)));
  @override
  bool shouldReclip(_Hole o) => o.r != r || o.center != center;
}

/// Dashed orbit rings that sweep on, the shockwave and the spark burst.
class _Fx extends CustomPainter {
  final Offset center;
  final double unit, rings, spin, shock, burst, fade;
  _Fx({required this.center, required this.unit, required this.rings, required this.spin, required this.shock, required this.burst, required this.fade});

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (i, (r, alpha, dir)) in [(92.0, .55, 1), (128.0, .30, -1), (168.0, .16, 1)].indexed) {
      final radius = r * unit;
      final n = (radius * 2 * pi / 15).round();
      final k = (rings * 1.4 - i * .12).clamp(0.0, 1.0); // each ring starts a beat later
      dash
        ..strokeWidth = (i == 0 ? 3.0 : 2.0) * unit
        ..color = (i == 1 ? C.amberLight : C.orange).withValues(alpha: alpha * fade);
      for (var s = 0; s < n * k; s++) {
        final a = dir * spin * (1 + i * .3) + s * 2 * pi / n;
        canvas.drawArc(Rect.fromCircle(center: center, radius: radius), a, 2 * pi / n * .5, false, dash);
      }
    }
    if (shock > 0 && shock < 1) {
      canvas.drawCircle(
          center,
          (74 + 420 * shock) * unit,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (5 * (1 - shock) + .5) * unit
            ..color = C.orange.withValues(alpha: .85 * (1 - shock)));
    }
    if (burst > 0 && burst < 1) {
      final spark = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3 * unit;
      for (var i = 0; i < 20; i++) {
        final a = i * 2 * pi / 20 + (i.isOdd ? .08 : 0);
        final start = (80 + (i.isEven ? 190 : 120) * burst) * unit;
        final len = (22 * (1 - burst) + 4) * unit;
        spark.color = (i % 3 == 0 ? C.textLight : (i.isEven ? C.orange : C.amberLight)).withValues(alpha: 1 - burst);
        canvas.drawLine(center + Offset(cos(a), sin(a)) * start, center + Offset(cos(a), sin(a)) * (start + len), spark);
      }
    }
  }

  @override
  bool shouldRepaint(_Fx o) => true;
}
