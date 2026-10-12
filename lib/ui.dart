import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'fx.dart';
import 'motion.dart';

class C {
  // Canvas & background
  static const bg = Color(0xFFF4F1EA); // warm linen
  static const canvas = Color(0xFFD8D2C3); // backdrop
  static const card = Color(0xFFFFFDF8); // warm white card
  static const surface = Color(0xFFFFFDF8);
  static const dark = Color(0xFF16140F); // deep warm charcoal / espresso
  static const cardDark = Color(0xFF24211B); // inner dark surface
  static const cardDarkElevated = Color(0xFF2A2720); // dark pill/button
  static const darkBar = Color(0xFF4A463B);

  // Borders & dividers
  static const border = Color(0xFFE3DDCF);
  static const borderLight = Color(0xFFEEE8DA);
  static const borderDark = Color(0xFF2E2B24);
  static const chipBg = Color(0xFFE8E2D3);
  static const chipLight = Color(0xFFF1ECDF);
  static const dividerDashed = Color(0xFFD9D2C1);

  // Text colors
  static const text = Color(0xFF16140F);
  static const textLight = Color(0xFFF4F1EA);
  static const muted = Color(0xFF6B6455);
  static const dim = Color(0xFF8A8374);
  static const dimLight = Color(0xFFA9A290);

  // Brand & semantic accents
  static const orange = Color(0xFFE4572E); // Hustler terracotta flame
  static const orangeDark = Color(0xFFB8401C);
  static const green = Color(0xFF2F7D5B); // forest green
  static const greenLight = Color(0xFFE4F1EA);
  static const greenText = Color(0xFF1F5C41);
  static const greenPaid = Color(0xFFCFE9DB);
  static const greenPaidText = Color(0xFF14513A);
  static const blue = Color(0xFF3B5B8C); // slate blue
  static const blueLight = Color(0xFFDCE6F4);
  static const blueText = Color(0xFF2B4A7A);
  static const amber = Color(0xFFC98A1B);
  static const amberLight = Color(0xFFE8C27A);
  static const red = Color(0xFFB8401C);
  static const redLight = Color(0xFFFBE9E2);
  static const redBorder = Color(0xFFF1C6B8);
  static const redText = Color(0xFF8A3A1F);
  static const draftBg = Color(0xFFECE6D7);
  static const draftText = Color(0xFF4A4538);
}

TextStyle display(double size, {Color color = C.text, FontWeight weight = FontWeight.w700}) => TextStyle(
      fontFamily: 'Grotesk',
      fontSize: size,
      fontWeight: weight,
      height: 1.05,
      letterSpacing: -0.5,
      color: color,
    );

TextStyle mono(double size, {Color color = C.dim, FontWeight weight = FontWeight.w500, double letterSpacing = 0.5}) => TextStyle(
      fontFamily: 'monospace',
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
    );

const muted = TextStyle(color: C.muted, fontSize: 13, fontFamily: 'Grotesk');

(Color, Color) statusStyle(String raw) {
  final s = raw.toLowerCase().trim();
  return switch (s) {
    'paid' => (C.greenPaid, C.greenPaidText),
    'accepted' || 'healthy' || 'active' => (C.greenLight, C.greenText),
    'sent' || 'downloading' => (C.blueLight, C.blueText),
    'overdue' || 'rejected' => (C.redLight, C.redText),
    'review' || 'partially_paid' || 'partial' || 'partially paid' => (C.amberLight.withValues(alpha: .35), C.text),
    'unpaid' => (C.blueLight, C.blueText),
    'done' => (C.greenPaid, C.greenPaidText),
    _ => (C.draftBg, C.draftText),
  };
}

Color statusColor(String s) => statusStyle(s).$2;

extension Entrance on Widget {
  /// Staggered entrance. Skipped entirely when the system asks for reduced motion.
  Widget enter(int i) => Builder(
        builder: (context) {
          if (MediaQuery.disableAnimationsOf(context)) return this;
          // Below the first screenful a one-shot entrance would play while the item is still off-screen, unseen. Those items
          // instead tip up and settle as they scroll into view (see fx.dart), which also works on the way back up.
          if (i >= 5 && Scrollable.maybeOf(context, axis: Axis.vertical) != null) return ScrollReveal.around(context, this);
          var a = animate(delay: (55 * min(i, 10)).ms)
              .fadeIn(duration: 380.ms, curve: Curves.easeOut)
              .slideY(begin: .14, duration: 650.ms, curve: const Cubic(.34, 1.4, .64, 1)) // spring overshoot
              .scaleXY(begin: .97, duration: 650.ms, curve: Curves.easeOutCubic);
          if (i < 3) a = a.blur(begin: const Offset(0, 5), end: Offset.zero, duration: 420.ms); // a blur filter per card is costly: top cards only
          return a;
        },
      );
}

Route<T> zoom<T>(Widget page) => PageRouteBuilder<T>(
      settings: RouteSettings(name: page.runtimeType.toString()), // shows up in the [nav] console log
      transitionDuration: 520.ms,
      reverseTransitionDuration: 340.ms,
      opaque: true, // once the push finishes the page below stops painting/ticking (Backdrop, pulses)
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (ctx, a, sec, child) {
        if (MediaQuery.disableAnimationsOf(ctx)) return child;
        final c = CurvedAnimation(parent: a, curve: const Cubic(.2, .9, .25, 1), reverseCurve: Curves.easeInCubic);
        final s2 = CurvedAnimation(parent: sec, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: Offset.zero, end: const Offset(-.18, 0)).animate(s2),
          child: FadeTransition(
            opacity: Tween(begin: 1.0, end: .0).animate(s2),
            child: SlideTransition(
              position: Tween(begin: const Offset(.22, 0), end: Offset.zero).animate(c),
              child: FadeTransition(
                opacity: c,
                child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(c), child: child),
              ),
            ),
          ),
        );
      },
    );

/// Pressable button with subtle spring feedback
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap, onLongPress;

  /// Screen-reader label. Leave null when [child] already contains readable text.
  final String? semanticLabel;

  /// Smallest touch target (logical px). A smaller child keeps its look and layout but its hit area grows to this size.
  static const minHit = 44.0;

  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.semanticLabel});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(mass: 1, stiffness: 600, damping: 17);
  late final c = AnimationController.unbounded(vsync: this, value: 1); // value = scale

  void _to(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      c.value = target == 1 ? 1 : .97; // reduced motion: no spring, just a tiny static press
      return;
    }
    c.animateWith(SpringSimulation(_spring, c.value, target, c.velocity));
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) return widget.child;
    return _MinHit(
      Semantics(
        button: true,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _to(.93),
          onTapUp: (_) => _to(1),
          onTapCancel: () => _to(1),
          onTap: widget.onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          onLongPress: widget.onLongPress,
          child: AnimatedBuilder(animation: c, builder: (_, child) => Transform.scale(scale: c.value, child: child), child: widget.child),
        ),
      ),
    );
  }
}

/// Grows the touch area of a small child to [Pressable.minHit] x [Pressable.minHit] without changing its layout.
class _MinHit extends SingleChildRenderObjectWidget {
  const _MinHit(Widget child) : super(child: child);
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMinHit();
}

class _RenderMinHit extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final dx = max(0.0, (Pressable.minHit - size.width) / 2), dy = max(0.0, (Pressable.minHit - size.height) / 2);
    if (position.dx < -dx || position.dx >= size.width + dx || position.dy < -dy || position.dy >= size.height + dy) return false;
    // a touch in the extra margin is forwarded as if it landed on the nearest edge of the child
    final p = Offset(position.dx.clamp(0.0, max(0.0, size.width - .01)), position.dy.clamp(0.0, max(0.0, size.height - .01)));
    return super.hitTest(result, position: p);
  }
}

/// Status Pill Badge
class StatusPill extends StatelessWidget {
  final String status;
  final bool uppercase;
  const StatusPill(this.status, {super.key, this.uppercase = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = statusStyle(status);
    final text = uppercase || status.isEmpty ? status.toUpperCase() : '${status[0].toUpperCase()}${status.substring(1)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: uppercase ? 'monospace' : 'Grotesk',
          letterSpacing: uppercase ? 0.6 : 0,
        ),
      ),
    );
  }
}

/// Warm white card
class CardContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;

  const CardContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.radius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final widgetChild = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? C.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? C.border),
      ),
      child: child,
    );
    return onTap != null ? Pressable(onTap: onTap, child: widgetChild) : widgetChild;
  }
}

/// Client Squircle Avatar
class AvatarSquircle extends StatelessWidget {
  final String name;
  final String? initial;
  final Color? color;
  final double size;

  const AvatarSquircle(this.name, {super.key, this.initial, this.color, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final ini = initial?.isNotEmpty == true
        ? initial!
        : (name.trim().isNotEmpty ? name.trim().characters.first.toUpperCase() : 'C'); // grapheme-safe (emoji)
    final bg = color ?? C.blue;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(size * 0.33),
        ),
        child: Text(
          ini,
          maxLines: 1,
          textScaler: TextScaler.noScaling, // the box is fixed size, so the letter must not grow with the system font size
          style: TextStyle(
            fontFamily: 'Grotesk',
            fontWeight: FontWeight.w700,
            fontSize: size * 0.42,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Segmented Switcher Pill
class PillSegmentedControl<T> extends StatelessWidget {
  final List<T> items;
  final T selected;
  final String Function(T) label;
  final int Function(T)? count;
  final ValueChanged<T> onSelected;

  const PillSegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.label,
    this.count,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: C.chipBg, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            for (final it in items)
              Expanded(
                child: Semantics(
                  selected: selected == it,
                  child: Pressable(
                    onTap: () => onSelected(it),
                    child: AnimatedContainer(
                      duration: 200.ms,
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected == it ? C.dark : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      // long labels / big text shrink to fit instead of overflowing
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label(it),
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'Grotesk',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected == it ? C.textLight : C.muted,
                              ),
                            ),
                            if (count != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                '${count!(it)}',
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: selected == it ? C.textLight.withValues(alpha: .7) : C.muted.withValues(alpha: .7),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Dual Progress Bar (Done % vs Budget %)
class DualProgressBar extends StatelessWidget {
  final double donePct;
  final double budgetPct;
  final Color? budgetColor;
  final bool stacked;

  const DualProgressBar({
    super.key,
    required this.donePct,
    required this.budgetPct,
    this.budgetColor,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final donePct = this.donePct.isFinite ? this.donePct : 0.0, budgetPct = this.budgetPct.isFinite ? this.budgetPct : 0.0; // NaN/inf never crash .round()
    final bColor = budgetColor ?? (budgetPct > donePct + 0.1 ? C.orange : C.green);
    final summary = 'Done ${(donePct * 100).round()} percent, budget ${(budgetPct * 100).round()} percent';

    if (stacked) {
      return Semantics(label: summary, child: Container(
        height: 12,
        decoration: BoxDecoration(color: C.draftBg, borderRadius: BorderRadius.circular(9)),
        child: Stack(
          children: [
            _Grow(
              budgetPct,
              Container(
                decoration: BoxDecoration(
                  color: bColor.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            _Grow(
              donePct,
              Container(
                decoration: BoxDecoration(
                  color: C.dark,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ],
        ),
      ));
    }

    return Semantics(label: summary, excludeSemantics: true, child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text('DONE ${(donePct * 100).round()}%', maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(11, color: C.muted))),
            const SizedBox(width: 8),
            Flexible(child: Text('BUDGET ${(budgetPct * 100).round()}%', maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(11, color: C.muted))),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 7,
          decoration: BoxDecoration(color: C.draftBg, borderRadius: BorderRadius.circular(9)),
          alignment: Alignment.centerLeft,
          child: _Grow(
            donePct,
            Container(
              decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(9)),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 7,
          decoration: BoxDecoration(color: C.draftBg, borderRadius: BorderRadius.circular(9)),
          alignment: Alignment.centerLeft,
          child: _Grow(
            budgetPct,
            Container(
              decoration: BoxDecoration(color: bColor, borderRadius: BorderRadius.circular(9)),
            ),
          ),
        ),
      ],
    ));
  }
}

/// Animates a bar's fill (0..1) from empty to [v]; vertical grows upward, otherwise left to right.
class _Grow extends StatelessWidget {
  final double v;
  final Widget child;
  final bool vertical;
  final int delay;
  const _Grow(this.v, this.child, {this.vertical = false, this.delay = 0});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: v.isFinite ? v.clamp(0.0, 1.0) : 0.0),
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Duration(milliseconds: 900 + delay),
        curve: Interval(delay / (900 + delay), 1, curve: Curves.easeOutCubic),
        builder: (_, f, _) => FractionallySizedBox(
          widthFactor: vertical ? null : f,
          heightFactor: vertical ? f : null,
          alignment: vertical ? Alignment.bottomCenter : Alignment.centerLeft,
          child: child,
        ),
      );
}

/// Cashflow 6-month Bar Chart
class CashflowBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final int activeIndex;

  const CashflowBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.activeIndex = 5,
  });

  @override
  Widget build(BuildContext context) {
    final vals = [for (final v in values) v.isFinite && v > 0 ? v : 0.0]; // NaN / negative never break the bars
    final maxV = vals.fold(1.0, (a, b) => max(a, b));
    return SizedBox(
      height: 62,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < vals.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: _Grow(
                          vals[i] == 0 ? .04 : (vals[i] / maxV).clamp(0.12, 1.0), // an empty month is a stub, not a bar
                          vertical: true,
                          delay: 90 * i,
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: i == activeIndex ? C.orange : C.darkBar,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(i < labels.length ? labels[i] : '', maxLines: 1, style: mono(9.5, color: C.dim))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Screen header with back button and breadcrumb tag
class SubScreenHeader extends StatelessWidget {
  final String backLabel;
  final String tag;
  final VoidCallback onBack;

  const SubScreenHeader({
    super.key,
    required this.backLabel,
    required this.tag,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Pressable(
                onTap: onBack,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: C.orangeDark),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          backLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Grotesk',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: C.orangeDark, // darker terracotta: the bright one is too faint on linen at 14px
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(tag.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(11, color: C.muted, letterSpacing: 1.0))),
          ],
        ),
      );
}

/// Big screen title with optional '+' add button
class Header extends StatelessWidget {
  final String title;
  final String? sub;
  final VoidCallback? onAdd;
  final String addLabel; // screen-reader label of the + button
  const Header(this.title, {super.key, this.sub, this.onAdd, this.addLabel = 'Add'});

  @override
  Widget build(BuildContext context) => ScrollParallax.around(context, _row());

  Widget _row() => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sub != null) Text(sub!, style: muted, maxLines: 2, overflow: TextOverflow.ellipsis),
                  SplitText(title, style: display(32)),
                ],
              ),
            ),
            if (onAdd != null)
              Semantics(
                button: true,
                label: addLabel,
                child: Padding(padding: const EdgeInsets.only(left: 12), child: Pressable(
                  onTap: onAdd,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: C.dark,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.add_rounded, color: C.textLight, size: 24),
                  ),
                )),
              ),
          ],
        ),
      );
}

class Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const Section(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(11, color: C.muted, letterSpacing: 1.0, weight: FontWeight.w700)),
              ),
            ),
            ?trailing,
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  const EmptyState(this.icon, this.title, this.sub, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        child: Column(
          children: [
            LivingBadge(icon), // a ring that draws itself, a turning dashed orbit and drifting sparkles round the floating icon
            const SizedBox(height: 12),
            Text(title, style: display(20), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(sub, style: muted, textAlign: TextAlign.center),
          ],
        ),
      );
}

/// Pushed screen wrapper
class Screen extends StatelessWidget {
  final String title;
  final String? subTag;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottom;
  const Screen({super.key, required this.title, this.subTag, required this.body, this.actions = const [], this.bottom});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        appBar: AppBar(
          backgroundColor: C.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: C.orange),
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context), // maybePop so a PopScope (unsaved-changes guard) is honoured
          ),
          scrolledUnderElevation: 0,
          title: Text(title, style: display(20), maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: actions,
        ),
        // edge-to-edge: keep content clear of the gesture / 3-button bar (the `bottom` area below does its own SafeArea)
        body: bottom == null ? SafeArea(top: false, child: ScrollProgress(child: body)) : ScrollProgress(child: body),
        bottomNavigationBar: bottom == null
            ? null
            : SafeArea(minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: bottom!),
      );
}

/// Labelled text input. [initial] is also followed when the underlying data changes from outside (a restore, a refresh),
/// as long as the user is not typing in it. Only [label], [initial] and [onChanged] are required.
class Field extends StatefulWidget {
  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboard;
  final int maxLines;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus, enabled;

  const Field(
    this.label,
    this.initial,
    this.onChanged, {
    super.key,
    this.keyboard,
    this.maxLines = 1,
    this.hint,
    this.validator,
    this.errorText,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
  });

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  late final TextEditingController ctl = TextEditingController(text: widget.initial);
  final focus = FocusNode();

  @override
  void didUpdateWidget(Field old) {
    super.didUpdateWidget(old);
    // the data changed behind our back (restore / refresh): show it. Never while typing (parse round-trips like "1." -> "1" would fight the user).
    if (widget.initial != old.initial && widget.initial != ctl.text && !focus.hasFocus) {
      ctl.value = TextEditingValue(text: widget.initial, selection: TextSelection.collapsed(offset: widget.initial.length));
    }
  }

  @override
  void dispose() {
    ctl.dispose();
    focus.dispose();
    super.dispose();
  }

  static OutlineInputBorder _border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Text(w.label.toUpperCase(), style: mono(10, color: C.muted, letterSpacing: 0.8))),
          const SizedBox(height: 4),
          Semantics(
            label: w.label,
            child: TextFormField(
              controller: ctl,
              focusNode: focus,
              onChanged: w.onChanged,
              onFieldSubmitted: w.onSubmitted,
              validator: w.validator,
              autovalidateMode: w.validator == null ? null : AutovalidateMode.onUserInteraction,
              keyboardType: w.keyboard ?? (w.maxLines > 1 ? TextInputType.multiline : null),
              textInputAction: w.textInputAction ?? (w.maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
              textCapitalization: w.textCapitalization,
              inputFormatters: w.inputFormatters,
              autofocus: w.autofocus,
              enabled: w.enabled,
              maxLines: w.maxLines,
              minLines: 1,
              cursorColor: C.orange,
              style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text),
              decoration: InputDecoration(
                hintText: w.hint,
                hintStyle: const TextStyle(color: C.dim, fontSize: 14),
                errorText: w.errorText,
                errorMaxLines: 3,
                errorStyle: const TextStyle(color: C.red, fontSize: 12, fontWeight: FontWeight.w600),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                fillColor: C.card,
                filled: true,
                border: _border(C.border),
                enabledBorder: _border(C.border),
                disabledBorder: _border(C.borderLight),
                focusedBorder: _border(C.dark, 1.5),
                errorBorder: _border(C.red),
                focusedErrorBorder: _border(C.red, 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Number -> text for an input box: empty for 0 / non-finite, no trailing ".0", no float noise like 0.30000000000000004.
String numText(double v) {
  if (v == 0 || !v.isFinite) return '';
  if (v % 1 == 0) return v.abs() < 1e15 ? v.toInt().toString() : v.toStringAsFixed(0);
  return v.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
}

double parseNum(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

final _destructiveVerb = RegExp(r'delete|remove|discard|clear|erase|reset|replace|restore|overwrite|wipe|cancel', caseSensitive: false);

/// Yes/no dialog. [verb] labels the confirming button; it is styled as destructive (terracotta red) when [destructive]
/// is true, or, if left null, when the verb reads like one (Delete, Remove, Restore ...). Scrolls at large text sizes.
Future<bool> confirm(BuildContext context, String title, String body, {String verb = 'Delete', bool? destructive}) async {
  final danger = destructive ?? _destructiveVerb.hasMatch(verb);
  final button = ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(64, 48)), overlayColor: WidgetStatePropertyAll((danger ? C.red : C.dark).withValues(alpha: .08)));
  return await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: C.card,
          scrollable: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: C.border)),
          title: Text(title, style: display(20)),
          content: Text(body, style: const TextStyle(fontFamily: 'Grotesk', color: C.muted, height: 1.35)),
          actions: [
            TextButton(style: button, onPressed: () => Navigator.pop(c, false), child: const Text('Cancel', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600))),
            TextButton(
              style: button,
              onPressed: () => Navigator.pop(c, true),
              child: Text(verb, style: TextStyle(color: danger ? C.red : C.text, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ) ??
      false;
}

/// Floating message. In the tab shell it sits above the bottom bar and the raised Magic button; on pushed screens above their `bottom` area.
void toast(BuildContext context, String msg, {SnackBarAction? action}) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.dark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      action: action,
      content: Text(msg, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.textLight, fontFamily: 'Grotesk', fontWeight: FontWeight.w600)),
    ),
  );

/// Date picker; [initial] is clamped into the allowed range so an old/odd stored date can never crash it.
Future<DateTime?> pickDate(BuildContext context, DateTime initial) {
  final first = DateTime(2015), last = DateTime(2100);
  final init = initial.isBefore(first) ? first : (initial.isAfter(last) ? last : initial);
  return showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: last);
}
