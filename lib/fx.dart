import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'ui.dart';

// Motion effects that are cheap by construction:
//  - scroll-driven effects are applied while painting (opacity and transform layers around a child that has its own repaint
//    boundary), so scrolling never rebuilds a widget and never re-rasterises the child;
//  - looping effects are one controller feeding one CustomPainter through `repaint:`, inside a RepaintBoundary;
//  - everything stops (draws its final frame) when the system asks for reduced motion.

// ------------------------------------------------------------------------------------------------------- scroll-driven

/// The nearest vertical Scrollable's position and its viewport box, or null when there isn't one (a bottom sheet, a plain Column).
class _Viewport {
  final ScrollPosition position;
  const _Viewport(this.position);
  static _Viewport? of(BuildContext context) {
    final s = Scrollable.maybeOf(context, axis: Axis.vertical);
    return s == null ? null : _Viewport(s.position);
  }
}

/// Where the child sits in its viewport while painting: its top edge measured from the viewport's top, and the viewport height.
(double top, double height)? _place(RenderBox self) {
  final RenderObject? found = RenderAbstractViewport.maybeOf(self);
  if (found is! RenderBox) return null;
  final RenderBox vp = found;
  if (!vp.hasSize || !self.attached) return null;
  if (vp is RenderViewport && vp.axis != Axis.vertical) return null;
  try {
    return (self.localToGlobal(Offset.zero, ancestor: vp).dy, vp.size.height);
  } catch (_) {
    return null; // not laid out yet
  }
}

abstract class _ScrollFxBox extends RenderProxyBox {
  _ScrollFxBox(this._position, RenderBox? child) : super(child);
  ScrollPosition? _position;

  set position(ScrollPosition? p) {
    if (identical(p, _position)) return;
    if (attached) _position?.removeListener(markNeedsPaint);
    _position = p;
    if (attached) _position?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _position?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  /// Paints the child with the effect for a viewport-relative [top] (null when unknown: paint plainly).
  void paintEffect(PaintingContext context, Offset offset, double top, double viewHeight);

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    final p = _place(this);
    if (p == null) {
      context.paintChild(c, offset);
      return;
    }
    paintEffect(context, offset, p.$1, p.$2);
  }

  /// Opacity layer + a transform about the child's centre. [tilt] rotates it about the x axis (perspective), like a card falling into place.
  void paintWith(PaintingContext context, Offset offset, {required double opacity, double dy = 0, double scale = 1, double tilt = 0}) {
    final c = child!;
    if (opacity <= 0.003) return;
    void inner(PaintingContext ctx, Offset off) {
      if (dy == 0 && scale == 1 && tilt == 0) {
        ctx.paintChild(c, off);
        return;
      }
      final center = Offset(size.width / 2, size.height / 2);
      final m = Matrix4.identity()
        ..setEntry(3, 2, 0.0011)
        ..translateByDouble(center.dx, center.dy + dy, 0, 1)
        ..rotateX(tilt)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-center.dx, -center.dy, 0, 1);
      ctx.pushTransform(true, off, m, (c2, o2) => c2.paintChild(c, o2));
    }

    if (opacity >= 0.997) {
      inner(context, offset);
    } else {
      context.pushOpacity(offset, (opacity * 255).round().clamp(0, 255), inner);
    }
  }
}

/// A card that tips up and settles as it scrolls into view (and eases away as it leaves at the top).
class _RenderScrollReveal extends _ScrollFxBox {
  _RenderScrollReveal(super.position, this.lift, super.child);
  final double lift;

  @override
  void paintEffect(PaintingContext context, Offset offset, double top, double h) {
    // revealed once its top edge is 20% of the viewport above the bottom edge
    final enter = ((h - top) / (h * .2)).clamp(0.0, 1.0);
    // fades while the last 14% of it leaves through the top
    final leave = ((top + size.height) / (h * .14)).clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(enter), l = Curves.easeOut.transform(leave);
    paintWith(context, offset,
        opacity: e * (.25 + .75 * l),
        dy: (1 - e) * lift - (1 - l) * 10,
        scale: (.92 + .08 * e) * (.97 + .03 * l),
        tilt: (1 - e) * .32);
  }
}

class ScrollReveal extends SingleChildRenderObjectWidget {
  final double lift;
  const ScrollReveal({super.key, super.child, this.lift = 44});

  @override
  RenderObject createRenderObject(BuildContext context) {
    final v = _Viewport.of(context);
    return _RenderScrollReveal(v?.position, lift, null);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderScrollReveal).position = _Viewport.of(context)?.position;
  }

  /// Wraps [child] only where the effect can work: inside a vertical scroll view, with motion allowed.
  static Widget around(BuildContext context, Widget child, {double lift = 44}) {
    if (MediaQuery.disableAnimationsOf(context) || _Viewport.of(context) == null) return child;
    return ScrollReveal(lift: lift, child: RepaintBoundary(child: child));
  }
}

/// A title that moves up slower than the page (parallax), shrinks and fades as it scrolls out through the top.
class _RenderScrollParallax extends _ScrollFxBox {
  _RenderScrollParallax(super.position, super.child);

  @override
  void paintEffect(PaintingContext context, Offset offset, double top, double h) {
    final up = (-top).clamp(0.0, 400.0); // how far its top edge is above the viewport
    final k = (up / 170).clamp(0.0, 1.0);
    paintWith(context, offset, opacity: 1 - k * .9, dy: up * .38, scale: 1 - k * .08);
  }
}

class ScrollParallax extends SingleChildRenderObjectWidget {
  const ScrollParallax({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScrollParallax(_Viewport.of(context)?.position, null);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderScrollParallax).position = _Viewport.of(context)?.position;
  }

  static Widget around(BuildContext context, Widget child) {
    if (MediaQuery.disableAnimationsOf(context) || _Viewport.of(context) == null) return child;
    return ScrollParallax(child: RepaintBoundary(child: child));
  }
}

/// Thin accent line under the app bar that fills as the page is scrolled (hidden until you scroll).
class ScrollProgress extends StatefulWidget {
  final Widget child;
  const ScrollProgress({super.key, required this.child});

  @override
  State<ScrollProgress> createState() => _ScrollProgressState();
}

class _ScrollProgressState extends State<ScrollProgress> {
  final p = ValueNotifier<double>(0);

  @override
  void dispose() {
    p.dispose();
    super.dispose();
  }

  bool _on(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final m = n.metrics.maxScrollExtent;
    p.value = m <= 0 ? 0 : (n.metrics.pixels / m).clamp(0.0, 1.0);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return NotificationListener<ScrollNotification>(
      onNotification: _on,
      child: Stack(fit: StackFit.expand, children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 4,
          child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _ProgressLine(p)))),
        ),
      ]),
    );
  }
}

class _ProgressLine extends CustomPainter {
  final ValueListenable<double> p;
  _ProgressLine(this.p) : super(repaint: p);

  @override
  void paint(Canvas canvas, Size size) {
    final v = p.value;
    if (v <= 0.002) return;
    final w = size.width * v;
    final rect = Rect.fromLTWH(0, 0, w, 3);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..shader = const LinearGradient(colors: [C.amber, C.orange, C.orangeDark]).createShader(Rect.fromLTWH(0, 0, max(size.width, 1), 3)));
    canvas.drawCircle(Offset(w, 1.5), 4.5, Paint()..color = C.orange.withValues(alpha: .45)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(Offset(w, 1.5), 1.8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ProgressLine o) => o.p != p;
}

// ------------------------------------------------------------------------------------------------------- celebration

/// A burst of confetti with a ring and check that draw themselves: for a paid invoice, an accepted quotation, a finished project.
class Celebrate {
  Celebrate._();

  static void burst(BuildContext context, {Offset? origin, bool big = true, bool haptic = true}) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final size = MediaQuery.sizeOf(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ConfettiLayer(origin: origin ?? Offset(size.width / 2, size.height * .36), big: big, onDone: () => entry.remove()),
    );
    overlay.insert(entry);
    if (haptic) HapticFeedback.heavyImpact();
  }
}

class _Particle {
  final double angle, speed, size, spin, delay, wobble;
  final int shape; // 0 rect, 1 circle, 2 streamer
  final Color color;
  const _Particle(this.angle, this.speed, this.size, this.spin, this.delay, this.wobble, this.shape, this.color);
}

class _ConfettiLayer extends StatefulWidget {
  final Offset origin;
  final bool big;
  final VoidCallback onDone;
  const _ConfettiLayer({required this.origin, required this.big, required this.onDone});

  @override
  State<_ConfettiLayer> createState() => _ConfettiLayerState();
}

class _ConfettiLayerState extends State<_ConfettiLayer> with SingleTickerProviderStateMixin {
  static const _colors = [C.orange, C.amber, C.green, C.blue, Color(0xFFFF8A4C), Color(0xFFE8C27A), Colors.white];
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.big ? 2600 : 1700))
    ..forward().whenComplete(widget.onDone);
  late final List<_Particle> particles = () {
    final r = Random();
    final n = widget.big ? 84 : 36;
    return [
      for (var i = 0; i < n; i++)
        _Particle(
          -pi / 2 + (r.nextDouble() - .5) * pi * 1.25, // a wide fan, mostly upward
          (widget.big ? 330 : 240) * (.45 + r.nextDouble() * .75),
          5 + r.nextDouble() * 6,
          (r.nextDouble() - .5) * 14,
          r.nextDouble() * .12,
          r.nextDouble() * pi * 2,
          r.nextInt(3),
          _colors[r.nextInt(_colors.length)],
        ),
    ];
  }();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(painter: _ConfettiPainter(c, particles, widget.origin, ring: widget.big, total: c.duration!.inMilliseconds / 1000)),
          ),
        ),
      );
}

class _ConfettiPainter extends CustomPainter {
  final Animation<double> c;
  final List<_Particle> ps;
  final Offset origin;
  final bool ring;
  final double total; // seconds
  _ConfettiPainter(this.c, this.ps, this.origin, {required this.ring, required this.total}) : super(repaint: c);

  @override
  void paint(Canvas canvas, Size size) {
    final secs = c.value * total;
    if (ring) _paintRing(canvas, secs);
    final paint = Paint();
    for (final p in ps) {
      final t = secs - p.delay;
      if (t <= 0) continue;
      // fast out of the cannon, then air drag and gravity take over
      final drag = 1 - exp(-t * 2.6);
      final x = origin.dx + cos(p.angle) * p.speed * drag / 2.6 * 1.0 + sin(t * 5 + p.wobble) * 10 * drag;
      final y = origin.dy + sin(p.angle) * p.speed * drag / 2.6 + 330 * t * t * .5;
      final life = (1 - (t - 1.1) / (total - 1.2)).clamp(0.0, 1.0);
      if (life <= 0 || y > size.height + 30) continue;
      paint.color = p.color.withValues(alpha: life);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * p.spin + p.wobble);
      switch (p.shape) {
        case 0:
          canvas.scale(1, cos(t * 7 + p.wobble).abs() * .9 + .1); // flips like paper
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * .6), paint);
        case 1:
          canvas.drawCircle(Offset.zero, p.size * .38, paint);
        default:
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size * .35, height: p.size * 1.9), const Radius.circular(2)), paint);
      }
      canvas.restore();
    }
  }

  /// A ring that sweeps round and a check that draws inside it, then both fade: SVG stroke-dashoffset, by hand.
  void _paintRing(Canvas canvas, double t) {
    final draw = Curves.easeOutCubic.transform((t / .55).clamp(0.0, 1.0));
    final check = Curves.easeOutCubic.transform(((t - .35) / .35).clamp(0.0, 1.0));
    final out = (1 - ((t - 1.2) / .5)).clamp(0.0, 1.0);
    if (out <= 0) return;
    final pop = 1 + .08 * sin(((t - .35) / .5).clamp(0.0, 1.0) * pi);
    const r = 38.0;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(pop);
    canvas.drawCircle(Offset.zero, r + 7, Paint()..color = C.green.withValues(alpha: .16 * out * draw));
    canvas.drawCircle(Offset.zero, r, Paint()..color = C.card.withValues(alpha: .96 * out));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = C.green.withValues(alpha: out);
    canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: r), -pi / 2, pi * 2 * draw, false, stroke);
    final path = Path()
      ..moveTo(-15, 1)
      ..lineTo(-4, 13)
      ..lineTo(17, -12);
    final m = path.computeMetrics().first;
    canvas.drawPath(m.extractPath(0, m.length * check), stroke..strokeWidth = 7);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConfettiPainter o) => false; // repainted by the animation itself
}

// ------------------------------------------------------------------------------------------------------- AI at work

/// An orbiting indicator for "the model is working": a sweeping arc, three dots on their own orbits with trails, a pulsing sparkle.
class AiOrbit extends StatefulWidget {
  final double size;
  final Color color;
  const AiOrbit({super.key, this.size = 22, this.color = C.orange});

  @override
  State<AiOrbit> createState() => _AiOrbitState();
}

class _AiOrbitState extends State<AiOrbit> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      c.stop();
    } else if (!c.isAnimating) {
      c.repeat();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(painter: _OrbitPainter(c, widget.color)),
          ),
        ),
      );
}

class _OrbitPainter extends CustomPainter {
  final Animation<double> c;
  final Color color;
  _OrbitPainter(this.c, this.color) : super(repaint: c);

  @override
  void paint(Canvas canvas, Size size) {
    final t = c.value * 2 * pi;
    final centre = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    // a comet arc: bright head fading back along the ring
    final rect = Rect.fromCircle(center: centre, radius: r);
    ring.shader = SweepGradient(startAngle: 0, endAngle: pi * 2, colors: [color.withValues(alpha: 0), color], transform: GradientRotation(t)).createShader(rect);
    canvas.drawArc(rect, t, pi * 1.5, false, ring);
    // three dots on different orbits, each with a short fading trail
    for (final (rad, speed, dot) in [(r * .62, 1.0, 2.2), (r * .4, -1.6, 1.7), (r * .8, 2.2, 1.4)]) {
      for (var k = 0; k < 5; k++) {
        final a = t * speed - k * .16 * speed.sign;
        canvas.drawCircle(centre + Offset(cos(a), sin(a)) * rad, dot * (1 - k * .15), Paint()..color = color.withValues(alpha: (1 - k * .22).clamp(0.0, 1.0)));
      }
    }
    // a sparkle that breathes in the middle
    final s = r * .3 * (1 + .25 * sin(t * 2));
    final star = Paint()..color = color..strokeWidth = 1.6..strokeCap = StrokeCap.round;
    canvas.drawLine(centre + Offset(0, -s), centre + Offset(0, s), star);
    canvas.drawLine(centre + Offset(-s, 0), centre + Offset(s, 0), star);
  }

  @override
  bool shouldRepaint(_OrbitPainter o) => o.color != color;
}

// ------------------------------------------------------------------------------------------------------- living illustration

/// The picture on an empty screen: the icon floats inside a ring that draws itself, a dashed orbit turns round it, sparkles drift.
class LivingBadge extends StatefulWidget {
  final IconData icon;
  const LivingBadge(this.icon, {super.key});

  @override
  State<LivingBadge> createState() => _LivingBadgeState();
}

class _LivingBadgeState extends State<LivingBadge> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 8));
  final born = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      c.stop();
    } else if (!c.isAnimating) {
      c.repeat();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: 104,
          height: 104,
          child: AnimatedBuilder(
            animation: c,
            builder: (_, _) {
              final t = c.value * 8; // seconds into the loop
              final bob = still ? 0.0 : sin(t * pi / 2 * .9) * 4;
              return CustomPaint(
                painter: _BadgePainter(c, still),
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, bob),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(color: C.draftBg, borderRadius: BorderRadius.circular(20)),
                      child: Icon(widget.icon, size: 28, color: C.muted),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  final Animation<double> c;
  final bool still;
  final DateTime born = DateTime.now();
  _BadgePainter(this.c, this.still) : super(repaint: c);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final spin = still ? 0.0 : c.value * 2 * pi;
    final age = still ? 9.0 : DateTime.now().difference(born).inMilliseconds / 1000;
    final draw = Curves.easeOutCubic.transform((age / 1.1).clamp(0.0, 1.0));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    // the ring draws itself once
    canvas.drawArc(Rect.fromCircle(center: centre, radius: 46), -pi / 2, pi * 2 * draw, false, line..color = C.orange.withValues(alpha: .35));
    // a dashed orbit that keeps turning
    final orbit = Path()..addOval(Rect.fromCircle(center: centre, radius: 38));
    final m = orbit.computeMetrics().first;
    const dash = 7.0, gap = 9.0;
    final off = (spin / (2 * pi)) * (dash + gap);
    line.color = C.dim.withValues(alpha: .35 * draw);
    for (var d = -off; d < m.length; d += dash + gap) {
      final a = max(d, 0.0), b = min(d + dash, m.length);
      if (b > a) canvas.drawPath(m.extractPath(a, b), line);
    }
    // sparkles drifting on their own paths
    for (final (rad, speed, ph, s) in [(46.0, 1.0, 0.0, 5.0), (40.0, -1.0, 2.2, 3.5), (49.0, 2.0, 4.1, 4.0)]) {
      final a = spin * speed + ph;
      final o = centre + Offset(cos(a), sin(a)) * rad;
      final twinkle = still ? 1.0 : .55 + .45 * sin(spin * 3 + ph * 2);
      final sp = Paint()
        ..color = C.orange.withValues(alpha: .7 * twinkle * draw)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(o + Offset(0, -s), o + Offset(0, s), sp);
      canvas.drawLine(o + Offset(-s, 0), o + Offset(s, 0), sp);
    }
  }

  @override
  bool shouldRepaint(_BadgePainter o) => false;
}

// ------------------------------------------------------------------------------------------------------- progress ring

/// A ring that sweeps to [value] (0..1) with a glowing head, and re-sweeps when the value changes.
class ProgressRing extends StatelessWidget {
  final double value, size;
  final Widget? child;
  final Color color;
  const ProgressRing({super.key, required this.value, this.size = 64, this.child, this.color = C.orange});

  @override
  Widget build(BuildContext context) {
    final v = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    final still = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: v),
        duration: still ? Duration.zero : const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, sweep, _) => CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(sweep, color),
          child: SizedBox(width: size, height: size, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  _RingPainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final w = size.width * .11;
    final r = (size.width - w) / 2;
    final rect = Rect.fromCircle(center: centre, radius: r);
    canvas.drawCircle(centre, r, Paint()..style = PaintingStyle.stroke..strokeWidth = w..color = C.border);
    if (v <= 0.002) return;
    final sweep = pi * 2 * v;
    canvas.drawArc(
      rect,
      -pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(startAngle: 0, endAngle: pi * 2, colors: [C.amber, color, C.orangeDark], transform: const GradientRotation(-pi / 2)).createShader(rect),
    );
    final head = centre + Offset(cos(-pi / 2 + sweep), sin(-pi / 2 + sweep)) * r;
    canvas.drawCircle(head, w * .9, Paint()..color = color.withValues(alpha: .35)..maskFilter = MaskFilter.blur(BlurStyle.normal, w * .6));
    canvas.drawCircle(head, w * .28, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

// ------------------------------------------------------------------------------------------------------- shared elements

/// A shared-element transition: the same [tag] on two screens makes the child fly from one to the other while the page changes.
/// (A bare Hero's flight has no Material above it, so any text in it would be drawn with the debug underline.)
class FlyTag extends StatelessWidget {
  final Object tag;
  final Widget child;
  const FlyTag(this.tag, {super.key, required this.child});

  @override
  Widget build(BuildContext context) => Hero(
        tag: tag,
        flightShuttleBuilder: (_, _, _, _, to) => Material(type: MaterialType.transparency, child: (to.widget as Hero).child),
        child: child,
      );
}
