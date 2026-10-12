import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'magic.dart';
import 'models.dart';
import 'motion.dart';
import 'projects.dart';
import 'settings.dart';
import 'state.dart';
import 'ui.dart';

/// Whole days from today to [d] (negative = in the past), ignoring the time of day and daylight-saving jumps.
int daysUntil(DateTime d, [DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
}

/// "3 DAYS OVERDUE", "TODAY", "TOMORROW", "IN 5 DAYS", or the date when it is further out.
String dueLabel(DateTime d, [DateTime? now]) {
  final n = daysUntil(d, now);
  if (n < 0) return '${-n} ${n == -1 ? 'DAY' : 'DAYS'} OVERDUE';
  if (n == 0) return 'TODAY';
  if (n == 1) return 'TOMORROW';
  if (n <= 14) return 'IN $n DAYS';
  return DateFormat('MMM d').format(d).toUpperCase();
}

/// Money collected (paid invoices, by invoice date) for each of the 6 months ending with the month of [now], oldest first.
List<({String label, double value})> trailingMonths(Iterable<Doc> invoices, [DateTime? now]) {
  final n = now ?? DateTime.now();
  return [
    for (var k = 5; k >= 0; k--)
      () {
        final m = DateTime(n.year, n.month - k);
        final sum = invoices
            .where((d) => d.isInvoice && d.status == 'paid' && d.date.year == m.year && d.date.month == m.month)
            .fold(0.0, (s, d) => s + d.total);
        return (label: DateFormat('MMM').format(m), value: sum);
      }(),
  ];
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final nav = context.read<NavController>();

    final activeProjects = s.projects.where((p) => p.status == 'active').toList();
    final pendingQuotes = s.docs.where((d) => !d.isInvoice && d.status == 'sent').length;
    final overdueDocs = s.docs.where((d) => d.overdue).toList();
    final overdueAmt = overdueDocs.fold(0.0, (a, d) => a + d.total);
    final outstanding = s.invoices.where((d) => d.status == 'sent' || d.status == 'overdue').fold(0.0, (a, d) => a + d.total);
    final collected = s.paid;
    final months = trailingMonths(s.docs);
    final hasChart = months.any((m) => m.value > 0);

    // Projects that still have work to do and a deadline, nearest first (overdue ones lead).
    final open = s.projects.where((p) => p.status != 'done').toList();
    final due = open.where((p) => p.deadline != null).toList()..sort((a, b) => a.deadline!.compareTo(b.deadline!));

    final now = DateTime.now();
    final dateStr = DateFormat('EEEE · MMM d').format(now).toUpperCase();
    final name = s.profile.bizName.trim().isNotEmpty ? s.profile.bizName.trim() : s.profile.ownerName.trim();
    final studioName = name.isEmpty ? 'Welcome' : name;

    // Health follows the money: anything overdue needs attention, otherwise any activity means on track.
    final (String, Color)? health = overdueAmt > 0 ? ('OVERDUE', C.red) : (collected > 0 || outstanding > 0 ? ('ON TRACK', C.green) : null);

    void openSettings() => Navigator.push(context, zoom(const SettingsPage()));
    var i = 0;

    return RefreshListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        // Date & studio name
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateStr, style: mono(11, color: C.dim, letterSpacing: 0.8)),
                const SizedBox(height: 4),
                SplitText(studioName, key: ValueKey(studioName), style: display(30), delayMs: 200),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: openSettings,
            child: Semantics(
              button: true,
              label: 'Settings',
              excludeSemantics: true,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(15), border: Border.all(color: C.border)),
                child: const Icon(Icons.settings_rounded, color: C.text, size: 22),
              ),
            ),
          ),
        ]).enter(i++),
        const SizedBox(height: 18),

        // First run: nothing about the owner is known yet
        if (s.needsSetup) ...[
          CardContainer(
            onTap: openSettings,
            color: C.redLight,
            borderColor: C.redBorder,
            radius: 20,
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Set up your studio', style: display(18)),
                  const SizedBox(height: 3),
                  const Text('Add your name, business details and payment info so your quotes and invoices carry them.',
                      style: TextStyle(fontSize: 12.5, color: C.redText, height: 1.35)),
                  const SizedBox(height: 6),
                  const Text('Open Settings', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.orange)),
                ]),
              ),
            ]),
          ).enter(i++),
          const SizedBox(height: 12),
        ],

        // Cash-flow health
        CardContainer(
          color: C.dark,
          borderColor: C.dark,
          radius: 24,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CASH-FLOW HEALTH', style: mono(10, color: C.dimLight, letterSpacing: 1.0)),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: CountUp(collected, format: money, style: display(34, color: C.textLight)),
                        ),
                        const SizedBox(height: 3),
                        Text('collected · ${money(outstanding)} outstanding',
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.dimLight, fontFamily: 'Grotesk')),
                      ],
                    ),
                  ),
                  if (health != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: health.$2, borderRadius: BorderRadius.circular(99)),
                      child: Text(health.$1, style: mono(11, color: Colors.white, weight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              if (hasChart)
                CashflowBarChart(values: [for (final m in months) m.value], labels: [for (final m in months) m.label], activeIndex: 5)
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  decoration: BoxDecoration(color: C.cardDark, borderRadius: BorderRadius.circular(14)),
                  child: const Text('Mark an invoice as paid and your last six months of income show up here.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: C.dimLight, height: 1.4)),
                ),
            ],
          ),
        ).enter(i++),
        const SizedBox(height: 12),

        // Metrics
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Metric(
                  value: CountUp(activeProjects.length.toDouble(), format: (v) => '${v.round()}', style: display(24)),
                  label: 'Active projects',
                  onTap: () => nav.go(NavController.projects),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  value: CountUp(pendingQuotes.toDouble(), format: (v) => '${v.round()}', style: display(24)),
                  label: 'Quotes pending',
                  onTap: () => nav.go(NavController.docs),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  hot: overdueDocs.isNotEmpty,
                  value: CountUp(overdueAmt, format: money, style: display(22, color: overdueDocs.isNotEmpty ? C.red : C.text)),
                  label: overdueDocs.length == 1 ? '1 overdue invoice' : (overdueDocs.isEmpty ? 'Overdue invoices' : '${overdueDocs.length} overdue invoices'),
                  onTap: () => nav.go(NavController.docs),
                ),
              ),
            ],
          ),
        ).enter(i++),
        const SizedBox(height: 12),

        // Magic Scratchpad banner
        Pressable(
          onTap: () => Navigator.push(context, zoom(const MagicPage())),
          child: Semantics(
            button: true,
            label: 'Open Magic Scratchpad',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(22)),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Magic Scratchpad', style: TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
                        SizedBox(height: 2),
                        Text('Jot rough notes. Turn them into a quote or invoice on your phone.',
                            style: TextStyle(fontFamily: 'Grotesk', fontSize: 12.5, color: Colors.white, height: 1.25)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .moveX(end: 5, duration: 700.ms, curve: Curves.easeInOut),
                ],
              ),
            ).animate(onPlay: (c) => c.repeat()).shimmer(delay: 2200.ms, duration: 1400.ms, color: Colors.white38),
          ),
        ).enter(i++),
        const SizedBox(height: 18),

        // Due soon: projects with a deadline
        Row(
          children: [
            Expanded(child: Text('Due soon', style: display(18))),
            Text('${due.length} ${due.length == 1 ? 'PROJECT' : 'PROJECTS'}', style: mono(11, color: C.dim)),
          ],
        ).enter(i++),
        const SizedBox(height: 8),
        CardContainer(
          padding: EdgeInsets.zero,
          radius: 18,
          child: due.isEmpty
              ? Pressable(
                  onTap: () => nav.go(NavController.projects),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        open.isEmpty
                            ? 'No active projects yet. Start one from the Projects tab.'
                            : 'No deadlines set. Add a deadline to a project and it shows up here.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: C.muted, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final (k, p) in due.take(4).indexed) ...[
                      if (k > 0) const Divider(height: 1, thickness: 1, color: C.borderLight),
                      _DueRow(project: p, clientName: s.clientName(p.clientId)),
                    ],
                    if (due.length > 4) ...[
                      const Divider(height: 1, thickness: 1, color: C.borderLight),
                      Pressable(
                        onTap: () => nav.go(NavController.projects),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          alignment: Alignment.center,
                          child: Text('${due.length - 4} more · see all projects', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.orange)),
                        ),
                      ),
                    ],
                  ],
                ),
        ).enter(i++),
        const SizedBox(height: 20),

        // Recent activity
        Row(children: [
          Text('Recent activity', style: display(18)),
          const SizedBox(width: 10),
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: C.green, shape: BoxShape.circle))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fade(begin: .35, end: 1, duration: 900.ms),
          const SizedBox(width: 5),
          Text('LIVE', style: mono(10, color: C.green, weight: FontWeight.w700, letterSpacing: 1)),
        ]).enter(i++),
        const SizedBox(height: 10),

        const _ActivityFeed().enter(i++),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final Widget value;
  final String label;
  final bool hot;
  final VoidCallback onTap;
  const _Metric({required this.value, required this.label, required this.onTap, this.hot = false});

  @override
  Widget build(BuildContext context) => CardContainer(
        color: hot ? C.redLight : null,
        borderColor: hot ? C.redBorder : null,
        padding: const EdgeInsets.all(12),
        radius: 16,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
            const SizedBox(height: 2),
            Text(label, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: hot ? C.redText : C.muted, height: 1.3)),
          ],
        ),
      );
}

class _DueRow extends StatelessWidget {
  final Project project;
  final String clientName;
  const _DueRow({required this.project, required this.clientName});

  @override
  Widget build(BuildContext context) {
    final p = project;
    final days = daysUntil(p.deadline!);
    final left = p.allLeaves.where((t) => !t.done).length;
    final tasks = p.totalTasksCount == 0 ? 'no tasks yet' : (left == 0 ? 'all tasks done' : '$left ${left == 1 ? 'task' : 'tasks'} left');
    final urgent = days <= 2;
    return Pressable(
      onTap: () => Navigator.push(context, zoom(ProjectDetailPage(p.id))),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: urgent ? C.red : (days <= 7 ? C.amber : C.dim), shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name.trim().isEmpty ? 'Untitled project' : p.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: C.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  Text('$clientName · $tasks', style: const TextStyle(fontSize: 12, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(dueLabel(p.deadline!),
                  textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: mono(11, color: urgent ? C.red : C.muted, weight: urgent ? FontWeight.w700 : FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Feed of what just happened, newest first. Rebuilt from the store on every change; a timer keeps "2 min ago" honest.
class _ActivityFeed extends StatefulWidget {
  const _ActivityFeed();
  @override
  State<_ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends State<_ActivityFeed> {
  late final Timer tick;

  @override
  void initState() {
    super.initState();
    tick = Timer.periodic(30.seconds, (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    tick.cancel();
    super.dispose();
  }

  static String ago(DateTime t, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final d = n.difference(t);
    if (d.inSeconds < 45) return 'JUST NOW';
    if (d.inMinutes < 60) return '${d.inMinutes} MIN AGO';
    final days = -daysUntil(t, n);
    if (days == 0) return 'TODAY ${DateFormat('H:mm').format(t)}';
    if (days == 1) return 'YESTERDAY';
    return DateFormat('MMM d').format(t).toUpperCase();
  }

  static Color tone(String t) => switch (t) { 'good' => C.green, 'info' => C.blue, 'bad' => C.red, _ => C.dim };

  @override
  Widget build(BuildContext context) {
    final items = context.watch<Store>().activity.take(6).toList();
    if (items.isEmpty) {
      return const CardContainer(
        radius: 18,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nothing yet. Invoices you send, tasks you finish and clients you add show up here as they happen.',
                textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 13, height: 1.4)),
          ),
        ),
      );
    }
    return Column(children: [
      for (final (k, a) in items.indexed)
        _TimelineItem(key: ValueKey(a.id), title: a.text, when: ago(a.at), color: tone(a.tone), isLast: k == items.length - 1)
            .animate(delay: (60 * k).ms)
            .fadeIn(duration: 350.ms)
            .slideY(begin: -.25, duration: 450.ms, curve: Curves.easeOutBack),
    ]);
  }
}

class _TimelineItem extends StatelessWidget {
  final String title;
  final String when;
  final Color color;
  final bool isLast;

  const _TimelineItem({super.key, required this.title, required this.when, required this.color, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                if (!isLast) Expanded(child: Container(width: 1, color: C.border, margin: const EdgeInsets.symmetric(vertical: 2))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: C.text, height: 1.35, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(when, style: mono(10.5, color: C.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
