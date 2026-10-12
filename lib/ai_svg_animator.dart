import 'dart:math' as math;
import 'package:flutter/material.dart';

/// GSAP-inspired AI SVG Vector Animator.
///
/// Renders a multi-layered, GPU-accelerated vector animation simulating GSAP
/// SVG animations:
/// - Counter-rotating orbital rings with animated dashed stroke-dashoffsets
/// - Morphing multi-harmonic AI neural spline core (MorphSVG style)
/// - Orbiting stardust nodes and sparkling quantum particles
/// - Glowing multi-stop chromatic radial energy aura
/// - Luminous 4-pointed AI starlight diamond with reflective facet highlights
class AiSvgAnimator extends StatefulWidget {
  final double size;
  final bool interactive;
  final VoidCallback? onTap;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final bool showGlow;

  const AiSvgAnimator({
    super.key,
    this.size = 64,
    this.interactive = false,
    this.onTap,
    this.primaryColor = const Color(0xFFFF5722), // Flame Orange
    this.secondaryColor = const Color(0xFFFFB300), // Amber Gold
    this.accentColor = const Color(0xFFFF8A65), // Coral highlight
    this.showGlow = true,
  });

  @override
  State<AiSvgAnimator> createState() => _AiSvgAnimatorState();
}

class _AiSvgAnimatorState extends State<AiSvgAnimator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (!still && !_controller.isAnimating) {
      _controller.repeat();
    } else if (still && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);

    Widget graphic = SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _AiSvgPainter(
              progress: still ? 0.25 : _controller.value,
              primary: widget.primaryColor,
              secondary: widget.secondaryColor,
              accent: widget.accentColor,
              showGlow: widget.showGlow,
            ),
          );
        },
      ),
    );

    if (widget.interactive && widget.onTap != null) {
      graphic = GestureDetector(
        onTap: widget.onTap,
        child: graphic,
      );
    }

    return graphic;
  }
}

class _AiSvgPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final Color accent;
  final bool showGlow;

  _AiSvgPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.showGlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final t = progress * 2 * math.pi;

    // 1. Ambient Energy Halo (GSAP Radial Glow)
    if (showGlow) {
      final pulse = 0.85 + 0.15 * math.sin(t * 2);
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: 0.38 * pulse),
            secondary.withValues(alpha: 0.14 * pulse),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.35));
      canvas.drawCircle(center, radius * 1.25 * pulse, glowPaint);
    }

    // 2. Outer Orbital Ring with animated dashed arcs (GSAP stroke-dashoffset)
    final outerRingRadius = radius * 0.88;
    final outerRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, size.width * 0.024)
      ..shader = SweepGradient(
        transform: GradientRotation(t),
        colors: [
          primary.withValues(alpha: 0.05),
          secondary.withValues(alpha: 0.9),
          accent,
          primary.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.45, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRingRadius));

    _drawDashedArc(
      canvas: canvas,
      center: center,
      radius: outerRingRadius,
      paint: outerRingPaint,
      startAngle: t * 1.2,
      dashLength: 0.32,
      gapLength: 0.18,
      dashesCount: 4,
    );

    // 3. Counter-rotating Inner Orbital Ellipse
    final innerRingRadius = radius * 0.68;
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.width * 0.018)
      ..color = accent.withValues(alpha: 0.55);

    _drawDashedArc(
      canvas: canvas,
      center: center,
      radius: innerRingRadius,
      paint: innerPaint,
      startAngle: -t * 1.5,
      dashLength: 0.4,
      gapLength: 0.35,
      dashesCount: 3,
    );

    // 4. Orbiting Stardust Spark Nodes (GSAP particle satellites)
    final numSatellites = 4;
    for (int i = 0; i < numSatellites; i++) {
      final angle = t * (i % 2 == 0 ? 1.4 : -1.1) + (i * 2 * math.pi / numSatellites);
      final orbitR = radius * (0.68 + 0.16 * math.sin(t + i));
      final satPos = Offset(
        center.dx + orbitR * math.cos(angle),
        center.dy + orbitR * math.sin(angle),
      );
      final satRadius = math.max(1.6, size.width * 0.035 * (0.8 + 0.4 * math.sin(t * 3 + i)));

      final satPaint = Paint()
        ..color = (i % 2 == 0 ? Colors.white : secondary).withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5);
      canvas.drawCircle(satPos, satRadius, satPaint);
    }

    // 5. Morphing AI Neural Spline Core (Simulates GSAP MorphSVG)
    final corePath = Path();
    final points = 8;
    final baseCoreRadius = radius * 0.44;
    for (int i = 0; i < points; i++) {
      final theta = (i * 2 * math.pi / points) + (t * 0.35);
      // Morphing oscillation along vertices:
      final morph = 0.28 * math.sin(t * 3 + i * 1.5) + 0.12 * math.cos(t * 2 + i);
      final r = (i % 2 == 0)
          ? baseCoreRadius * (1.18 + morph)
          : baseCoreRadius * (0.65 - morph * 0.5);
      final px = center.dx + r * math.cos(theta);
      final py = center.dy + r * math.sin(theta);
      if (i == 0) {
        corePath.moveTo(px, py);
      } else {
        corePath.lineTo(px, py);
      }
    }
    corePath.close();

    final coreGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFFFF8A50),
        primary,
        const Color(0xFFD84315),
      ],
    ).createShader(Rect.fromCircle(center: center, radius: baseCoreRadius * 1.2));

    final corePaint = Paint()
      ..shader = coreGradient
      ..style = PaintingStyle.fill;
    canvas.drawPath(corePath, corePaint);

    // 6. Central Glowing 4-Point AI Sparkle Star (The Signature AI Nexus)
    final starScale = 1.0 + 0.08 * math.sin(t * 4);
    final starRadiusOuter = radius * 0.36 * starScale;
    final starRadiusInner = radius * 0.09 * starScale;
    final starPath = _createStarPath(center, 4, starRadiusOuter, starRadiusInner, t * 0.15);

    final starPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.96)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.8);
    canvas.drawPath(starPath, starPaint);

    // 7. Micro Starlight Glint in Star Core
    final glintPaint = Paint()
      ..color = Colors.white
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.5);
    canvas.drawCircle(center, radius * 0.08, glintPaint);
  }

  void _drawDashedArc({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required Paint paint,
    required double startAngle,
    required double dashLength,
    required double gapLength,
    required int dashesCount,
  }) {
    for (int i = 0; i < dashesCount; i++) {
      final sweepAngle = dashLength;
      final currentStart = startAngle + i * (dashLength + gapLength);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        currentStart,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  Path _createStarPath(Offset center, int points, double outerR, double innerR, double rotation) {
    final path = Path();
    final totalPoints = points * 2;
    for (int i = 0; i < totalPoints; i++) {
      final angle = (i * math.pi / points) + rotation;
      final r = i.isEven ? outerR : innerR;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _AiSvgPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.showGlow != showGlow;
  }
}
