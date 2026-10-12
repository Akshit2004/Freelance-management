import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'ai.dart';
import 'clients.dart';
import 'docs.dart';
import 'models.dart';
import 'motion.dart';
import 'ui.dart';

String _stageLabel(String s) => switch (s) { 'active' => 'Active', 'review' => 'Review', 'done' => 'Done', _ => 'Active' };

/// A project with a status we don't know (e.g. from an old backup) is shown under Active so it never disappears.
String _stageOf(Project p) => projectStatuses.contains(p.status) ? p.status : 'active';

/// Share of the budget already invoiced (0 when there is no budget, so the bars never get NaN/Infinity).
double _budgetPct(Store s, Project p) => p.budget > 0 ? s.projectInvoiced(p.id) / p.budget : 0.0;

Color _budgetColor(double bpct, Project p) => bpct > 1 ? C.red : (bpct > p.progress + 0.1 ? C.orange : C.green);

const _minTap = BoxConstraints(minHeight: 44, minWidth: 44);

// ---------------------------------------------------------------------------------------------------------------- tab

class ProjectsTab extends StatefulWidget {
  const ProjectsTab({super.key});
  @override
  State<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends State<ProjectsTab> {
  String stage = 'active'; // which tab is open: purely local UI state

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final list = s.projects.where((p) => _stageOf(p) == stage).toList();
    int count(String st) => s.projects.where((p) => _stageOf(p) == st).length;
    var i = 0;

    return RefreshListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: SplitText('Projects', style: display(32))),
              Semantics(
                button: true,
                label: 'New project',
                child: Tooltip(
                  message: 'New project',
                  child: Pressable(
                    onTap: () => newProject(context),
                    child: Container(
                      key: const Key('new-project'),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(15)),
                      child: const Icon(Icons.add_rounded, color: C.textLight, size: 24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ).enter(i++),
        PillSegmentedControl<String>(
          items: projectStatuses,
          selected: stage,
          label: _stageLabel,
          count: count,
          onSelected: (v) => setState(() => stage = v),
        ).enter(i++),
        const SizedBox(height: 14),
        if (s.projects.isEmpty) ...[
          const EmptyState(Icons.folder_open_rounded, 'No projects yet', 'Projects hold your tasks, deadline and the invoices you send for the work.'),
          Center(child: _PrimaryButton('New project', Icons.add_rounded, () => newProject(context))),
        ] else if (list.isEmpty)
          EmptyState(Icons.folder_open_rounded, 'Nothing in ${_stageLabel(stage)}', 'Change a project\'s status to move it here.')
        else
          for (final p in list) ...[
            _ProjectCard(project: p, bpct: _budgetPct(s, p), client: s.client(p.clientId)?.name).enter(i++),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PrimaryButton(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: C.textLight, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: const TextStyle(color: C.textLight, fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 15))),
          ]),
        ),
      );
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final double bpct;
  final String? client;
  const _ProjectCard({required this.project, required this.bpct, required this.client});

  @override
  Widget build(BuildContext context) {
    final p = project;
    final deadline = p.status == 'done' ? null : p.deadlineLabel();
    final next = p.nextTask;
    final clientName = client ?? 'Unknown client';
    final late = p.isLate();
    final detail = [
      '${(p.progress * 100).round()}% done',
      ?deadline,
      if (p.budget > 0) '${(bpct * 100).round()}% of budget invoiced',
    ].join(', ');

    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: '${p.name}, $clientName, $detail',
      child: CardContainer(
        radius: 20,
        padding: const EdgeInsets.all(16),
        onTap: () => Navigator.push(context, zoom(ProjectDetailPage(p.id))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name.isEmpty ? 'Untitled project' : p.name, style: display(18), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(clientName, style: const TextStyle(fontSize: 12.5, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (deadline != null || next != null) ...[
              const SizedBox(height: 10),
              if (deadline != null)
                Row(children: [
                  Icon(Icons.event_rounded, size: 14, color: late ? C.red : C.dim),
                  const SizedBox(width: 5),
                  Expanded(child: Text(deadline, style: mono(11, color: late ? C.red : C.muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              if (next != null) ...[
                if (deadline != null) const SizedBox(height: 3),
                Text('Next: ${next.text}', style: const TextStyle(fontSize: 12.5, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
            const SizedBox(height: 14),
            if (p.budget > 0)
              DualProgressBar(donePct: p.progress, budgetPct: min(bpct, 1.0), budgetColor: _budgetColor(bpct, p))
            else
              _WorkOnlyBar(p),
          ],
        ),
      ),
    );
  }
}

/// Progress bar for a project without a budget (the budget row would only say "0%", which would be misleading).
class _WorkOnlyBar extends StatelessWidget {
  final Project p;
  const _WorkOnlyBar(this.p);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('DONE ${(p.progress * 100).round()}%', style: mono(11, color: C.muted)),
            Flexible(child: Text(p.totalTasksCount == 0 ? 'NO TASKS YET' : 'NO BUDGET SET', style: mono(11, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Container(
            height: 7,
            decoration: BoxDecoration(color: C.draftBg, borderRadius: BorderRadius.circular(9)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: p.progress.clamp(0.0, 1.0),
              child: Container(decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(9))),
            ),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------------------------------------- detail

class ProjectDetailPage extends StatelessWidget {
  final String projectId;
  const ProjectDetailPage(this.projectId, {super.key});

  Future<void> _delete(BuildContext context, Project pr) async {
    final docs = context.read<Store>().docsOfProject(pr.id).length;
    final linked = docs == 0
        ? ''
        : '\n\nThe $docs linked ${docs == 1 ? 'invoice or quote is' : 'invoices and quotes are'} kept, but will no longer be linked to a project.';
    final ok = await confirm(context, 'Delete project?', '"${pr.name}" and its tasks will be removed. This can\'t be undone.$linked');
    if (!ok || !context.mounted) return;
    context.read<Store>().deleteProject(pr.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final pr = s.project(projectId);
    if (pr == null) {
      return const Screen(title: 'Project', body: EmptyState(Icons.folder_off_outlined, 'Project not found', 'It may have been deleted.'));
    }

    final client = s.client(pr.clientId);
    final bpct = _budgetPct(s, pr);
    final bColor = _budgetColor(bpct, pr);
    final invoiced = s.projectInvoiced(pr.id), paid = s.projectPaid(pr.id);
    final docs = s.docsOfProject(pr.id);
    final deadline = pr.deadlineLabel();
    final late = pr.isLate();
    final verdict = pr.budget <= 0
        ? 'No budget set. Edit the project to add one.'
        : invoiced > pr.budget
            ? 'Invoiced ${money(invoiced - pr.budget)} over the budget.'
            : bpct > pr.progress + 0.1
                ? 'Billing (${(bpct * 100).round()}%) is ahead of the work done (${(pr.progress * 100).round()}%).'
                : 'Billing is in line with the work done. ${money(pr.budget - invoiced)} left to bill.';
    var i = 0;

    return Screen(
      title: 'Project',
      actions: [
        IconButton(
          tooltip: 'Edit project',
          icon: const Icon(Icons.edit_outlined, color: C.text, size: 22),
          onPressed: () => Navigator.push(context, zoom(ProjectEdit(pr))),
        ),
        IconButton(
          tooltip: 'Delete project',
          icon: const Icon(Icons.delete_outline_rounded, color: C.red, size: 22),
          onPressed: () => _delete(context, pr),
        ),
      ],
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          // ---- header: what, for whom, by when, which stage
          Text(pr.name.isEmpty ? 'Untitled project' : pr.name, style: display(28), maxLines: 4, overflow: TextOverflow.ellipsis).enter(i++),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              client == null
                  ? const _Chip(icon: Icons.person_off_outlined, label: 'Unknown client')
                  : Semantics(
                      button: true,
                      label: 'Client ${client.name}. Open client',
                      excludeSemantics: true,
                      child: Pressable(
                        onTap: () => Navigator.push(context, zoom(ClientDetailPage(client.id))),
                        child: Container(
                          key: const Key('client-chip'),
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                          decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(99), border: Border.all(color: C.border)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AvatarSquircle(client.name, initial: client.ini, color: Color(client.colorValue), size: 28),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(client.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: C.text)),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: C.dim),
                            ],
                          ),
                        ),
                      ),
                    ),
              _Chip(
                icon: pr.status == 'done' ? Icons.check_circle_outline_rounded : Icons.event_rounded,
                label: pr.status == 'done' ? 'Completed' : (deadline == null ? 'No deadline set' : '$deadline · ${fmtDate(pr.deadline!)}'),
                color: late ? C.red : null,
              ),
            ],
          ).enter(i++),
          const SizedBox(height: 14),
          PillSegmentedControl<String>(
            items: projectStatuses,
            selected: projectStatuses.contains(pr.status) ? pr.status : 'active',
            label: _stageLabel,
            onSelected: (v) => context.read<Store>().setProjectStatus(pr.id, v),
          ).enter(i++),
          const SizedBox(height: 16),

          // ---- brief: the description, which is also what the AI estimate reads
          CardContainer(
            padding: const EdgeInsets.all(16),
            radius: 20,
            onTap: pr.notes.trim().isEmpty ? () => Navigator.push(context, zoom(ProjectEdit(pr))) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BRIEF', style: mono(10, color: C.muted, letterSpacing: .8)),
                const SizedBox(height: 6),
                pr.notes.trim().isEmpty
                    ? const Text('No description yet. Tap to add what the client needs, so the AI estimate has something to read.',
                        style: TextStyle(fontSize: 13, color: C.dim, height: 1.4))
                    : Text(pr.notes.trim(), style: const TextStyle(fontSize: 14, color: C.text, height: 1.45)),
              ],
            ),
          ).enter(i++),
          const SizedBox(height: 12),

          // ---- AI estimate: sits between the brief it reads and the deliverables it fills
          CardContainer(
            padding: const EdgeInsets.all(16),
            radius: 20,
            color: C.chipLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: C.orange.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.auto_awesome_rounded, color: C.orangeDark, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('AI estimate', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                        SizedBox(height: 2),
                        Text('Budget, hours and deliverables with subtasks, from the title and brief. On-device.',
                            style: TextStyle(fontSize: 12, color: C.muted, height: 1.35)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _AiReviewButton(pr),
              ],
            ),
          ).enter(i++),
          const SizedBox(height: 12),

          // ---- progress
          CardContainer(
            padding: const EdgeInsets.all(16),
            radius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PROGRESS', style: mono(10, color: C.muted, letterSpacing: .8)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _Stat('${(pr.progress * 100).round()}%', 'complete')),
                  Expanded(child: _Stat('${pr.doneTasksCount}/${pr.totalTasksCount}', 'tasks done')),
                  Expanded(child: _Stat(pr.hoursEstimate > 0 ? Todo.fmtHours(pr.hoursEstimate) : '0h', 'estimated')),
                ]),
                const SizedBox(height: 14),
                DualProgressBar(donePct: pr.progress, budgetPct: min(bpct, 1.0), budgetColor: bColor, stacked: true),
                if (pr.budget > 0) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 14, runSpacing: 4, children: [
                    _Legend(C.dark, 'Work done'),
                    _Legend(bColor.withValues(alpha: .4), 'Budget invoiced'),
                  ]),
                ],
              ],
            ),
          ).enter(i++),
          const SizedBox(height: 20),

          // ---- deliverables
          _SectionRow(
            'Deliverables',
            count: pr.totalTasksCount == 0 ? null : '${pr.doneTasksCount}/${pr.totalTasksCount}',
            action: _MiniButton('Add', Icons.add_rounded, () => _taskSheet(context, pr.id), key: const Key('add-task')),
          ),
          const SizedBox(height: 8),
          CardContainer(
            padding: EdgeInsets.zero,
            radius: 18,
            child: pr.todos.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('No deliverables yet. Tap Add, or let the AI estimate suggest them.',
                            textAlign: TextAlign.center, style: TextStyle(color: C.muted))),
                  )
                : Column(
                    children: [
                      for (var idx = 0; idx < pr.todos.length; idx++) ...[
                        if (idx > 0) const Divider(height: 1, thickness: 1, color: C.border),
                        _TaskRow(
                          todo: pr.todos[idx],
                          onToggle: () => context.read<Store>().toggleTodo(pr.id, pr.todos[idx].id),
                          onEdit: () => _taskDetail(context, pr.id, pr.todos[idx].id),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 24),

          // ---- money
          CardContainer(
            padding: const EdgeInsets.all(16),
            radius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MONEY', style: mono(10, color: C.muted, letterSpacing: .8)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _MoneyTile('Budget', pr.budget > 0 ? money(pr.budget) : 'Not set', strong: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _MoneyTile('Invoiced', money(invoiced))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _MoneyTile('Paid', money(paid), color: paid > 0 ? C.greenText : null)),
                  const SizedBox(width: 8),
                  Expanded(child: _MoneyTile('Awaiting payment', money(invoiced - paid), color: invoiced - paid > 0 ? C.orangeDark : null)),
                ]),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(pr.budget <= 0 ? Icons.info_outline_rounded : (bColor == C.green ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded),
                        size: 16, color: pr.budget <= 0 ? C.dim : bColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(verdict, style: const TextStyle(fontSize: 12.5, color: C.muted, height: 1.4))),
                ]),
              ],
            ),
          ).enter(i++),
          const SizedBox(height: 20),

          // ---- documents
          _SectionRow('Documents', count: docs.isEmpty ? null : '${docs.length}'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _MiniButton('New invoice', Icons.receipt_long_outlined, () => _newDoc(context, pr, 'invoice'), key: const Key('new-invoice'))),
            const SizedBox(width: 8),
            Expanded(child: _MiniButton('New quote', Icons.request_quote_outlined, () => _newDoc(context, pr, 'quote'), key: const Key('new-quote'))),
          ]),
          const SizedBox(height: 10),
          CardContainer(
            padding: EdgeInsets.zero,
            radius: 18,
            child: docs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No invoices or quotes for this project yet.', textAlign: TextAlign.center, style: TextStyle(color: C.muted))),
                  )
                : Column(
                    children: [
                      for (var k = 0; k < docs.length; k++) ...[
                        if (k > 0) const Divider(height: 1, thickness: 1, color: C.borderLight),
                        _DocRow(docs[k]),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _newDoc(BuildContext context, Project pr, String kind) =>
      Navigator.push(context, zoom(DocEditor(context.read<Store>().newDoc(kind, clientId: pr.clientId, projectId: pr.id), isNew: true)));
}

/// Reads the project's title and description with the on-device model, shows its budget / hours / deliverables, and saves them on approval.
class _AiReviewButton extends StatefulWidget {
  final Project project;
  const _AiReviewButton(this.project);

  @override
  State<_AiReviewButton> createState() => _AiReviewButtonState();
}

class _AiReviewButtonState extends State<_AiReviewButton> {
  bool busy = false;
  String progress = ''; // 'Reviewing…' becomes 'Reviewing 3/6…' while the features of each deliverable are written

  Future<void> _review() async {
    if (busy) return;
    final pr = widget.project, s = context.read<Store>();
    if (pr.name.trim().isEmpty && pr.notes.trim().isEmpty) {
      toast(context, 'Add a title or description first');
      return;
    }
    if (!Ai.ready) {
      toast(context, 'Install an on-device model in Settings first');
      return;
    }
    setState(() {
      busy = true;
      progress = '';
    });
    final est = await Ai.estimate(pr.name.trim(), pr.notes.trim(), s.profile.currency, s.profile.hourlyRate, onProgress: (done, total) {
      if (mounted) setState(() => progress = ' $done/$total');
    });
    if (!mounted) return;
    setState(() => busy = false);
    if (est == null) {
      toast(context, 'Could not estimate this project. ${Ai.estimateNote}');
      return;
    }
    final ok = await confirm(
      context,
      'AI estimate',
      'Budget: ${money(est.budget)}${pr.budget > 0 ? ' (replaces ${money(pr.budget)})' : ''}\n'
      '${est.fromRate ? '${Todo.fmtHours(est.hours)} × ${money(s.profile.hourlyRate)}/h' : '${Todo.fmtHours(est.hours)}. Price guessed by the model; set your hourly rate in Settings to price it as hours × rate.'}\n\n'
      '${est.todos.map((t) => [
            '• ${t.text} · ${Todo.fmtHours(Project(todos: [t]).hoursEstimate)}',
            for (final sub in t.sub) '    – ${sub.text} · ${sub.hours}',
          ].join('\n')).join('\n')}',
      verb: 'Save',
      destructive: false,
    );
    if (!ok || !mounted) return;
    s.applyEstimate(pr.id, est.budget, est.todos);
    toast(context, 'Estimate saved to the project');
  }

  @override
  Widget build(BuildContext context) =>
      _MiniButton(busy ? 'Reviewing$progress…' : 'Review with AI', Icons.auto_awesome_rounded, _review, key: const Key('ai-review'));
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: display(26), maxLines: 1)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11.5, color: C.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      );
}

/// One figure in the money grid.
class _MoneyTile extends StatelessWidget {
  final String label, value;
  final bool strong;
  final Color? color;
  const _MoneyTile(this.label, this.value, {this.strong = false, this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: strong ? C.chipLight : C.bg, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: mono(strong ? 16 : 14, color: color ?? C.text, weight: strong ? FontWeight.w700 : FontWeight.w600), maxLines: 1),
          ),
        ]),
      );
}

/// Small rounded label with an icon (deadline, unknown client). [color] marks it as a warning.
class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _Chip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color == null ? C.card : C.redLight,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color == null ? C.border : C.redBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color ?? C.dim),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: color ?? C.muted, fontWeight: color == null ? FontWeight.w500 : FontWeight.w700)),
          ),
        ]),
      );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11.5, color: C.muted)),
      ]);
}

class _SectionRow extends StatelessWidget {
  final String title;
  final String? count;
  final Widget? action;
  const _SectionRow(this.title, {this.count, this.action});

  @override
  Widget build(BuildContext context) => Row(children: [
        Flexible(child: Text(title, style: display(18), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (count != null) ...[const SizedBox(width: 8), Text(count!, style: mono(11, color: C.muted))],
        const Spacer(),
        ?action,
      ]);
}

class _MiniButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _MiniButton(this.label, this.icon, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          constraints: _minTap,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: C.chipLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: C.orangeDark),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.orangeDark))),
          ]),
        ),
      );
}

class _DocRow extends StatelessWidget {
  final Doc d;
  const _DocRow(this.d);

  @override
  Widget build(BuildContext context) {
    final kind = d.isInvoice ? 'Invoice' : 'Quote';
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$kind ${d.number}, ${d.title}, ${money(d.total)}, ${d.status}',
      child: Pressable(
        onTap: () => Navigator.push(context, zoom(DocDetailPage(d.id))),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${kind.toUpperCase()} · ${d.number}', style: mono(11, color: C.dim), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(d.title.isEmpty ? kind : d.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                FittedBox(fit: BoxFit.scaleDown, child: Text(money(d.total), style: mono(13, color: C.text), maxLines: 1)),
                const SizedBox(height: 4),
                StatusPill(d.shownStatus),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------------------ tasks

String _priLabel(String p) => switch (p) { 'high' => 'High', 'low' => 'Low', _ => 'Medium' };

/// A deliverable's total hours: its subtasks' hours, or its own when it has none (same rule as the project total).
String _hoursOf(Todo t) => t.sub.isEmpty ? t.hours.trim() : Todo.fmtHours(Project(todos: [t]).hoursEstimate);

class _TaskRow extends StatelessWidget {
  final Todo todo;
  final bool isSub;
  final VoidCallback onToggle, onEdit; // onEdit: a deliverable opens its detail sheet, a subtask its edit sheet
  const _TaskRow({required this.todo, this.isSub = false, required this.onToggle, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final hours = _hoursOf(todo);
    final subs = todo.sub.isEmpty ? '' : '${todo.sub.where((s) => s.done).length}/${todo.sub.length} subtasks';
    final hasTag = hours.isNotEmpty || subs.isNotEmpty || (todo.priority == 'high' || todo.priority == 'low');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: isSub ? 22 : 4),
        Semantics(
          checked: todo.done,
          label: todo.text,
          onTap: onToggle,
          excludeSemantics: true,
          child: Pressable(
            onTap: onToggle,
            child: SizedBox(
              key: Key('toggle-${todo.id}'),
              width: 44,
              height: 48,
              child: Center(
                child: AnimatedContainer(
                  duration: 320.ms,
                  curve: Curves.easeOutBack,
                  width: 21,
                  height: 21,
                  decoration: BoxDecoration(
                    color: todo.done ? C.orange : Colors.transparent,
                    borderRadius: BorderRadius.circular(todo.done ? 11 : 7),
                    border: Border.all(color: todo.done ? C.orange : C.dim, width: 1.8),
                  ),
                  child: Center(child: DrawCheck(on: todo.done, size: 13)),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            button: true,
            excludeSemantics: true,
            label: '${todo.text}, ${_priLabel(todo.priority)} priority${hours.isEmpty ? '' : ', $hours'}${subs.isEmpty ? '' : ', $subs'}. ${isSub ? 'Edit' : 'Open'}',
            child: Pressable(
              onTap: onEdit,
              child: Container(
                key: Key('edit-${todo.id}'),
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.fromLTRB(2, 10, 12, 10),
                alignment: Alignment.centerLeft,
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AnimatedDefaultTextStyle(
                        duration: 300.ms,
                        style: TextStyle(
                          fontFamily: 'Grotesk',
                          fontSize: isSub ? 13 : 14.5,
                          fontWeight: isSub ? FontWeight.w400 : FontWeight.w600,
                          decoration: todo.done ? TextDecoration.lineThrough : null,
                          color: todo.done ? C.dim : C.text,
                        ),
                        child: Text(todo.text, maxLines: 4, overflow: TextOverflow.ellipsis),
                      ),
                      if (hasTag) ...[
                        const SizedBox(height: 4),
                        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          if (hours.isNotEmpty) Text(hours, style: mono(11, color: C.muted)),
                          if (subs.isNotEmpty) Text(subs, style: mono(11, color: C.muted)),
                          if (todo.priority == 'high') _PriTag('High', C.redText, C.redLight),
                          if (todo.priority == 'low') _PriTag('Low', C.muted, C.chipLight),
                        ]),
                      ],
                    ]),
                  ),
                  const SizedBox(width: 6),
                  Icon(isSub ? Icons.more_horiz_rounded : Icons.chevron_right_rounded, size: 18, color: C.dim),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PriTag extends StatelessWidget {
  final String label;
  final Color fg, bg;
  const _PriTag(this.label, this.fg, this.bg);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ]),
      );
}

/// What opens when a deliverable is tapped: its subtasks, with buttons to edit it or add a subtask. Stays live while edit sheets open on top of it.
void _taskDetail(BuildContext context, String projectId, String todoId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _TaskDetail(projectId, todoId),
    );

class _TaskDetail extends StatelessWidget {
  final String projectId, todoId;
  const _TaskDetail(this.projectId, this.todoId);

  Todo? _find(BuildContext context) => context.read<Store>().project(projectId)?.todos.where((t) => t.id == todoId).firstOrNull;

  /// Opens an edit sheet on top of this one; if the deliverable was deleted there, this sheet closes too.
  Future<void> _over(BuildContext context, {Todo? todo, String? parentId}) async {
    await _taskSheet(context, projectId, todo: todo, parentId: parentId);
    if (context.mounted && _find(context) == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final t = s.project(projectId)?.todos.where((x) => x.id == todoId).firstOrNull;
    if (t == null) return const SizedBox(height: 1); // deleted while open; _over closes the sheet
    final hours = _hoursOf(t);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.text, style: display(22), maxLines: 4, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (hours.isNotEmpty) Text(hours, style: mono(12, color: C.muted)),
            if (t.sub.isNotEmpty) Text('${t.sub.where((x) => x.done).length}/${t.sub.length} subtasks done', style: mono(12, color: C.muted)),
            if (t.priority == 'high') const _PriTag('High', C.redText, C.redLight),
            if (t.priority == 'low') const _PriTag('Low', C.muted, C.chipLight),
          ]),
          const SizedBox(height: 16),
          Text('SUBTASKS', style: mono(10, color: C.dim, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          CardContainer(
            padding: EdgeInsets.zero,
            radius: 16,
            color: C.bg,
            child: t.sub.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                        child: Text('No subtasks yet. Add the steps this deliverable needs.', textAlign: TextAlign.center, style: TextStyle(color: C.muted))),
                  )
                : Column(children: [
                    for (var i = 0; i < t.sub.length; i++) ...[
                      if (i > 0) const Divider(height: 1, thickness: 1, color: C.borderLight),
                      _TaskRow(
                        todo: t.sub[i],
                        isSub: true,
                        onToggle: () => context.read<Store>().toggleSub(projectId, t.id, t.sub[i].id),
                        onEdit: () => _over(context, todo: t.sub[i]),
                      ),
                    ],
                  ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Pressable(
                onTap: () => _over(context, parentId: t.id),
                child: Container(
                  key: const Key('detail-add-sub'),
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: C.chipLight, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                  child: const Text('Add subtask', style: TextStyle(color: C.orangeDark, fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Pressable(
                onTap: () => _over(context, todo: t),
                child: Container(
                  key: const Key('detail-edit'),
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(16)),
                  child: const Text('Edit', style: TextStyle(color: C.textLight, fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Add a deliverable (no [todo], no [parentId]), add a subtask ([parentId]) or edit [todo]. Everything goes through Store intents.
Future<void> _taskSheet(BuildContext context, String projectId, {Todo? todo, String? parentId}) async {
  final r = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _TaskSheet(projectId, todo: todo, parentId: parentId),
  );
  if (r == 'sub' && todo != null && context.mounted) _taskSheet(context, projectId, parentId: todo.id);
}

class _TaskSheet extends StatefulWidget {
  final String projectId;
  final Todo? todo;
  final String? parentId;
  const _TaskSheet(this.projectId, {this.todo, this.parentId});

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final text = TextEditingController(text: widget.todo?.text ?? '');
  late final hours = TextEditingController(text: widget.todo == null || widget.todo!.hoursValue == 0 ? '' : numText(widget.todo!.hoursValue));
  late String priority = widget.todo?.priority ?? 'med';
  bool tried = false;

  bool get isSub => widget.parentId != null || (widget.todo != null && _isSubtask);
  bool get _isSubtask => context.read<Store>().project(widget.projectId)?.todos.every((t) => t.id != widget.todo!.id) ?? false;

  @override
  void dispose() {
    text.dispose();
    hours.dispose();
    super.dispose();
  }

  double? get hoursNum {
    final t = hours.text.trim().replaceAll(',', '.');
    return t.isEmpty ? 0 : double.tryParse(t);
  }

  String? get textErr => tried && text.text.trim().isEmpty ? 'Give it a name' : null;
  String? get hoursErr => tried && (hoursNum == null || hoursNum! < 0 || hoursNum! > 9999) ? 'Enter hours as a number, like 2 or 1.5' : null;

  void _save() {
    setState(() => tried = true);
    if (textErr != null || hoursErr != null) return;
    final s = context.read<Store>();
    final label = text.text.trim(), h = Todo.fmtHours(hoursNum!);
    final t = widget.todo;
    if (t != null) {
      s.editTodo(widget.projectId, t.id, text: label, priority: priority, hours: h);
    } else if (widget.parentId != null) {
      s.addSub(widget.projectId, widget.parentId!, Todo(text: label, priority: priority, hours: h));
    } else {
      s.addTodo(widget.projectId, Todo(text: label, priority: priority, hours: h));
    }
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final t = widget.todo!;
    final ok = await confirm(
      context,
      'Delete ${isSub ? 'subtask' : 'deliverable'}?',
      t.sub.isEmpty ? '"${t.text}" will be removed.' : '"${t.text}" and its ${t.sub.length} subtasks will be removed.',
    );
    if (!ok || !mounted) return;
    context.read<Store>().deleteTodo(widget.projectId, t.id);
    Navigator.pop(context);
  }

  InputDecoration _dec(String hint, {String? error, String? suffix}) => InputDecoration(
        hintText: hint,
        errorText: error,
        suffixText: suffix,
        hintStyle: const TextStyle(color: C.dim, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: C.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.dark, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.todo != null;
    final noun = isSub ? 'subtask' : 'deliverable';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit $noun' : 'New $noun', style: display(20)),
            const SizedBox(height: 14),
            TextField(
              key: const Key('task-text'),
              controller: text,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              maxLines: 3,
              minLines: 1,
              onChanged: (_) => tried ? setState(() {}) : null,
              style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text),
              decoration: _dec('e.g. Pastry spread illustration', error: textErr),
            ),
            const SizedBox(height: 12),
            Text('ESTIMATED HOURS', style: mono(10, color: C.dim, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            TextField(
              key: const Key('task-hours'),
              controller: hours,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onChanged: (_) => tried ? setState(() {}) : null,
              onSubmitted: (_) => _save(),
              style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text),
              decoration: _dec('Optional', error: hoursErr, suffix: 'h'),
            ),
            if (!isSub) ...[
              const SizedBox(height: 12),
              Text('PRIORITY', style: mono(10, color: C.dim, letterSpacing: 0.8)),
              const SizedBox(height: 4),
              PillSegmentedControl<String>(
                items: const ['high', 'med', 'low'],
                selected: priority,
                label: _priLabel,
                onSelected: (v) => setState(() => priority = v),
              ),
            ],
            const SizedBox(height: 18),
            Pressable(
              onTap: _save,
              child: Container(
                key: const Key('task-save'),
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(16)),
                child: Text(editing ? 'Save changes' : 'Add $noun',
                    style: const TextStyle(color: C.textLight, fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            if (editing) ...[
              const SizedBox(height: 8),
              Wrap(alignment: WrapAlignment.spaceBetween, children: [
                if (!isSub) TextButton.icon(
                  key: const Key('task-add-sub'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: () => Navigator.pop(context, 'sub'),
                  icon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 18, color: C.orangeDark),
                  label: const Text('Add subtask', style: TextStyle(color: C.orangeDark, fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  key: const Key('task-delete'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: C.red),
                  label: const Text('Delete', style: TextStyle(color: C.red, fontWeight: FontWeight.w700)),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------------------------------- create / edit

/// Starts the new-project flow. A project needs a client, so with none yet this offers to create one first.
Future<void> newProject(BuildContext context, [String clientId = '']) async {
  if (context.read<Store>().clients.isEmpty) {
    final ok = await confirm(context, 'Add a client first', 'Every project belongs to a client. Add one now?', verb: 'Add client');
    if (!ok || !context.mounted) return;
    final c = await Navigator.push<Client>(context, zoom(ClientEdit(Client(), isNew: true)));
    if (c == null || !context.mounted) return;
    clientId = c.id;
  }
  Navigator.push(context, zoom(ProjectEdit(Project(clientId: clientId), isNew: true)));
}

class ProjectEdit extends StatefulWidget {
  final Project project;
  final bool isNew;
  const ProjectEdit(this.project, {super.key, this.isNew = false});

  @override
  State<ProjectEdit> createState() => _ProjectEditState();
}

class _ProjectEditState extends State<ProjectEdit> {
  late final p = widget.project.copy();
  late String budgetText = numText(p.budget);
  late final DateTime? originalDeadline = widget.project.deadline;
  bool tried = false;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  double? get budgetNum {
    final t = budgetText.replaceAll(',', '').trim();
    return t.isEmpty ? 0 : double.tryParse(t);
  }

  String? clientErr(Store s) => tried && s.client(p.clientId) == null ? 'Choose a client' : null;
  String? get nameErr => tried && p.name.trim().isEmpty ? 'Give the project a name' : null;
  String? get budgetErr {
    final b = budgetNum;
    return b == null || b < 0 || b.isInfinite || b > 1e12 ? 'Enter an amount like 25000 or 1500.50' : null;
  }

  String? get deadlineErr {
    final d = p.deadline;
    if (d == null || (originalDeadline != null && d == originalDeadline)) return null;
    return d.isBefore(_today) ? 'The deadline can\'t be in the past' : null;
  }

  void _save(Store s) {
    setState(() => tried = true);
    final err = nameErr ?? clientErr(s) ?? budgetErr ?? deadlineErr;
    if (err != null) {
      toast(context, err);
      return;
    }
    p
      ..name = p.name.trim()
      ..budget = budgetNum!;
    s.putProject(p);
    Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final first = originalDeadline != null && originalDeadline!.isBefore(_today) ? originalDeadline! : _today;
    final d = await showDatePicker(
      context: context,
      initialDate: p.deadline == null || p.deadline!.isBefore(first) ? _today : p.deadline!,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => p.deadline = d);
  }

  Future<void> _addClient() async {
    final c = await Navigator.push<Client>(context, zoom(ClientEdit(Client(), isNew: true)));
    if (c != null && mounted) setState(() => p.clientId = c.id);
  }

  InputDecoration _dec({String? hint, String? error, String? prefix}) => InputDecoration(
        hintText: hint,
        errorText: error,
        prefixText: prefix,
        hintStyle: const TextStyle(color: C.dim, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: C.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.dark, width: 1.5)),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t.toUpperCase(), style: mono(10, color: C.dim, letterSpacing: 0.8)),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    const style = TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text);
    final cErr = clientErr(s);
    final hasClient = s.client(p.clientId) != null;
    final today = _today;
    final dErr = deadlineErr;

    return Screen(
      title: widget.isNew ? 'New project' : 'Edit project',
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          _label('Project name'),
          TextFormField(
            key: const Key('project-name'),
            initialValue: p.name,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            style: style,
            onChanged: (v) => setState(() => p.name = v),
            decoration: _dec(error: nameErr),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _label('Client')),
            TextButton.icon(
              key: const Key('add-client'),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: _addClient,
              icon: const Icon(Icons.add_rounded, size: 16, color: C.orangeDark),
              label: const Text('New client', style: TextStyle(color: C.orangeDark, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ]),
          if (s.clients.isEmpty)
            Text('You have no clients yet. Add one to create this project.', style: TextStyle(color: cErr == null ? C.muted : C.red, fontSize: 13))
          else
            DropdownButtonFormField<String>(
              key: ValueKey('client-${p.clientId}-${s.clients.length}'),
              initialValue: hasClient ? p.clientId : null,
              isExpanded: true,
              hint: const Text('Choose a client'),
              style: style,
              items: [
                for (final c in s.clients)
                  DropdownMenuItem(value: c.id, child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
              ],
              onChanged: (v) => setState(() => p.clientId = v ?? ''),
              decoration: _dec(error: cErr),
            ),
          const SizedBox(height: 14),
          _label('Budget (optional)'),
          TextFormField(
            key: const Key('project-budget'),
            initialValue: budgetText,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            style: style,
            onChanged: (v) => setState(() => budgetText = v),
            decoration: _dec(hint: 'e.g. 25000', prefix: '${s.profile.currency} ', error: tried ? budgetErr : null),
          ),
          const SizedBox(height: 14),
          _label('Deadline (optional)'),
          Row(children: [
            Expanded(
              child: Pressable(
                onTap: _pickDate,
                child: Container(
                  key: const Key('project-deadline'),
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: dErr == null ? C.border : C.red),
                  ),
                  child: Row(children: [
                    const Icon(Icons.event_rounded, size: 18, color: C.dim),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        p.deadline == null ? 'No deadline' : fmtDate(p.deadline!),
                        style: TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: p.deadline == null ? C.dim : C.text),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            if (p.deadline != null)
              IconButton(
                key: const Key('clear-deadline'),
                tooltip: 'Remove deadline',
                constraints: _minTap,
                icon: const Icon(Icons.close_rounded, size: 20, color: C.muted),
                onPressed: () => setState(() => p.deadline = null),
              ),
          ]),
          if (dErr != null) Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text(dErr, style: const TextStyle(color: C.red, fontSize: 12))),
          if (p.deadline != null && dErr == null && p.deadline!.isBefore(today))
            const Padding(padding: EdgeInsets.only(top: 6, left: 4), child: Text('This deadline has already passed.', style: TextStyle(color: C.muted, fontSize: 12))),
          const SizedBox(height: 14),
          _label('Status'),
          PillSegmentedControl<String>(
            items: projectStatuses,
            selected: projectStatuses.contains(p.status) ? p.status : 'active',
            label: _stageLabel,
            onSelected: (v) => setState(() => p.status = v),
          ),
          const SizedBox(height: 14),
          _label('Notes (optional)'),
          TextFormField(
            initialValue: p.notes,
            maxLines: 5,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            style: style,
            onChanged: (v) => p.notes = v,
            decoration: _dec(hint: 'Scope, links, anything to remember'),
          ),
        ],
      ),
      bottom: Pressable(
        onTap: () => _save(s),
        child: Container(
          key: const Key('project-save'),
          width: double.infinity,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(16)),
          child: Text(widget.isNew ? 'Create project' : 'Save changes',
              style: const TextStyle(color: C.textLight, fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    );
  }
}
