import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai.dart';
import 'builder_widgets.dart';
import 'clients.dart';
import 'docs.dart';
import 'magic.dart' show parseNotes;
import 'models.dart';
import 'templates.dart';
import 'ui.dart';

// The quotation builder and the invoice builder: two separate screens with their own steps, started from the Documents tab,
// a client page or a project page. Both finish on the document's page, where it can still be edited, previewed and shared.

double? _num(String t) => t.trim().isEmpty ? null : double.tryParse(t.trim().replaceAll(',', ''));

int? _termDays(String terms) {
  final t = terms.trim().toLowerCase();
  if (t == 'due on receipt') return 0;
  final m = RegExp(r'^net\s*(\d{1,3})$').firstMatch(t);
  return m == null ? null : int.parse(m.group(1)!);
}

const _payTerms = ['Due on receipt', 'Net 7', 'Net 14', 'Net 30'];

/// One line on its way into a document: the line itself, the deliverable it describes, and where that deliverable came from.
class BuilderLine {
  final LineItem item;
  final Todo part; // the deliverable (with its features as subtasks) that the scope and timeline are written from
  final bool existing; // an existing project deliverable (picked), not one made up by the builder
  final bool generated; // written by "Generate"; a new Generate replaces these and keeps the rest
  BuilderLine(this.item, this.part, {this.existing = false, this.generated = false});
}

InputDecoration _dec(String hint, {String? error}) => InputDecoration(
      hintText: hint,
      errorText: error,
      errorMaxLines: 2,
      hintStyle: const TextStyle(color: C.dim, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      filled: true,
      fillColor: C.bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.dark, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.red)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.red, width: 1.5)),
    );

/// Client and project pickers shared by both builders.
class _ClientProject extends StatelessWidget {
  final String clientId, projectId;
  final String? error;
  final ValueChanged<String> onClient, onProject;
  final VoidCallback onNewClient;
  const _ClientProject({required this.clientId, required this.projectId, required this.onClient, required this.onProject, required this.onNewClient, this.error});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final projects = [for (final p in s.projects) if (p.clientId == clientId) p];
    final project = projects.any((p) => p.id == projectId) ? projectId : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (s.clients.isEmpty)
        Pressable(
          onTap: onNewClient,
          child: Container(
            key: const Key('builder-new-client'),
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: error == null ? C.border : C.red)),
            child: const Text('+ Add your first client', style: TextStyle(fontWeight: FontWeight.w700, color: C.orangeDark)),
          ),
        )
      else ...[
        DropdownButtonFormField<String>(
          key: ValueKey('client-$clientId-${s.clients.length}'),
          initialValue: s.client(clientId) == null ? null : clientId,
          isExpanded: true,
          hint: const Text('Choose a client'),
          decoration: _dec('', error: error),
          items: [for (final c in s.clients) DropdownMenuItem(value: c.id, child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => v == null ? null : onClient(v),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: C.orange, padding: const EdgeInsets.symmetric(horizontal: 4)),
            onPressed: onNewClient,
            child: const Text('+ New client', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ),
      ],
      if (projects.isNotEmpty) ...[
        const SizedBox(height: 4),
        builderLabel('Project'),
        DropdownButtonFormField<String>(
          key: ValueKey('project-$clientId-$project'),
          initialValue: project,
          isExpanded: true,
          decoration: _dec(''),
          items: [
            const DropdownMenuItem(value: '', child: Text('No project')),
            for (final p in projects) DropdownMenuItem(value: p.id, child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => onProject(v ?? ''),
        ),
      ],
    ]);
  }
}

Future<String?> _newClient(BuildContext context) async {
  final created = await Navigator.push<Object?>(context, zoom(ClientEdit(Client(), isNew: true)));
  if (created is Client && context.mounted && context.read<Store>().client(created.id) != null) return created.id;
  return null;
}

/// A list of lines with edit / remove, and the buttons to add more.
class _Lines extends StatelessWidget {
  final List<BuilderLine> lines;
  final ValueChanged<BuilderLine> onEdit, onRemove;
  final String emptyText;
  const _Lines({required this.lines, required this.onEdit, required this.onRemove, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(emptyText, style: const TextStyle(fontSize: 13, color: C.muted, height: 1.4)));
    }
    return Column(children: [
      for (final (i, l) in lines.indexed) ...[
        if (i > 0) const Divider(height: 1, thickness: 1, color: C.borderLight),
        Semantics(
          button: true,
          label: 'Edit ${l.item.desc.split('\n').first}',
          excludeSemantics: true,
          child: Pressable(
            onTap: () => onEdit(l),
            child: Container(
              key: Key('line-$i'),
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.item.desc.split('\n').first, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    if (l.item.desc.contains('\n'))
                      Text(l.item.desc.split('\n').skip(1).join(' '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: C.muted, height: 1.3)),
                    Text(
                      '${numText(l.item.qty)}${l.item.unit == 'x' ? '' : ' ${l.item.unit}'} × ${money(l.item.rate)}${l.item.todoId != null && l.existing ? '  ·  linked' : ''}',
                      style: mono(11, color: C.dim),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(money(l.item.amount), style: mono(14, color: C.text, weight: FontWeight.w600))),
                ),
                IconButton(
                  tooltip: 'Remove ${l.item.desc.split('\n').first}',
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: const Icon(Icons.delete_outline_rounded, color: C.red, size: 20),
                  onPressed: () => onRemove(l),
                ),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }
}

Widget _action(String label, IconData icon, VoidCallback? onTap, {Key? key, bool dark = false}) => Pressable(
      onTap: onTap,
      child: Container(
        key: key,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dark ? C.dark : C.chipLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dark ? C.dark : C.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: dark ? C.textLight : C.orangeDark),
          const SizedBox(width: 6),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: dark ? C.textLight : C.orangeDark))),
        ]),
      ),
    );

Widget _bottomBar(String caption, String total, String label, VoidCallback? onTap, {Key? key}) => Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .2), blurRadius: 18, offset: const Offset(0, 6))]),
      child: Row(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(caption, style: mono(9.5, color: C.dimLight, letterSpacing: .6)),
              FittedBox(fit: BoxFit.scaleDown, child: Text(total, style: display(18, color: C.textLight))),
            ]),
          ),
        ),
        Pressable(
          onTap: onTap,
          child: Container(
            key: key,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: onTap == null ? C.dimLight : C.orange, borderRadius: BorderRadius.circular(18)),
            child: Text(label, style: const TextStyle(color: Colors.white, fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ]),
    );

// ------------------------------------------------------------------------------------------------------------ quotation

/// Build a quotation from a plain description of the job: pick a template, describe the work, and it writes the items, scope,
/// features table, timeline, payment schedule and the terms and conditions you switch on.
class QuoteBuilderPage extends StatefulWidget {
  final String clientId;
  final String? projectId;
  const QuoteBuilderPage({super.key, this.clientId = '', this.projectId});

  @override
  State<QuoteBuilderPage> createState() => _QuoteBuilderPageState();
}

class _QuoteBuilderPageState extends State<QuoteBuilderPage> {
  String template = 'proposal';
  late String clientId = widget.clientId, projectId = widget.projectId ?? '';
  final brief = TextEditingController(), title = TextEditingController();
  late final TextEditingController taxCtl;
  final discountCtl = TextEditingController(text: '0');
  int revisions = 2, validity = 30;
  String planId = 'half', payTerms = 'Net 14';
  double late = 0;
  late Set<String> clauses = templatesFor('quote', template).clauses.toSet();
  final lines = <BuilderLine>[];
  bool addToProject = true, busy = false, tried = false;
  String progress = '';

  @override
  void initState() {
    super.initState();
    taxCtl = TextEditingController(text: numText(context.read<Store>().profile.defaultTax));
  }

  @override
  void dispose() {
    for (final c in [brief, title, taxCtl, discountCtl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setTemplate(String id) => setState(() {
        template = id;
        clauses = templatesFor('quote', id).clauses.toSet();
      });

  QuoteSpec _spec(Store s) => QuoteSpec(
        brief: brief.text,
        clientName: s.client(clientId)?.name ?? '',
        bizName: s.profile.bizName.trim().isNotEmpty ? s.profile.bizName : s.profile.ownerName,
        paymentTerms: payTerms,
        revisions: revisions,
        validityDays: validity,
        latePct: late,
        clauses: clauses,
        parts: [for (final l in lines) l.part],
      );

  Doc _draft() => Doc(kind: 'quote', items: [for (final l in lines) l.item], taxPct: _num(taxCtl.text) ?? 0, discount: _num(discountCtl.text) ?? 0);

  Future<void> _generate() async {
    if (busy) return;
    final text = brief.text.trim();
    if (text.isEmpty) {
      toast(context, 'Describe the job first');
      return;
    }
    FocusScope.of(context).unfocus();
    final s = context.read<Store>();
    final cur = s.profile.currency, rate = s.profile.hourlyRate;
    final name = title.text.trim().isEmpty ? titleFromBrief(text) : title.text.trim();
    setState(() {
      busy = true;
      progress = '';
    });
    ProjectEstimate? est;
    if (Ai.ready) {
      est = await Ai.estimate(name, text, cur, rate, onProgress: (d, t) {
        if (mounted) setState(() => progress = ' $d/$t');
      });
    }
    if (!mounted) return;
    final fresh = <BuilderLine>[];
    String note;
    if (est != null) {
      final eff = rate > 0 ? rate : (est.hours > 0 ? round2(est.budget / est.hours) : 0.0);
      for (final t in est.todos) {
        fresh.add(BuilderLine(lineForDeliverable(t, eff), t, generated: true));
      }
      note = rate > 0 ? 'Written on-device. Priced at your hourly rate; check the hours.' : 'Written on-device. The model guessed the price; check it, or set an hourly rate in Settings.';
    } else {
      // no model, or it failed: read priced lines such as "logo 3 @ 500" from the text, else start with one empty-priced line
      for (final i in parseNotes(text, s.clients, cur).items) {
        fresh.add(BuilderLine(LineItem(desc: i.desc, qty: i.qty, unit: i.unit.isEmpty ? 'x' : i.unit, rate: i.rate), Todo(text: i.desc), generated: true));
      }
      if (fresh.isEmpty) fresh.add(BuilderLine(LineItem(desc: name), Todo(text: name), generated: true));
      note = Ai.ready ? 'The model could not estimate this (${Ai.estimateNote}). Set the prices below.' : 'No AI model is installed, so only priced lines in your text were read. Set the prices below.';
    }
    setState(() {
      busy = false;
      if (title.text.trim().isEmpty) title.text = name;
      lines
        ..removeWhere((l) => l.generated)
        ..insertAll(0, fresh);
    });
    toast(context, note);
  }

  Future<void> _fromDeliverables() async {
    if (projectId.isEmpty) {
      toast(context, 'Choose a project first');
      return;
    }
    final rate = context.read<Store>().profile.hourlyRate;
    final picked = await pickDeliverables(context, projectId: projectId, used: {for (final l in lines) if (l.existing) l.part.id});
    if (picked == null || !mounted) return;
    setState(() {
      for (final t in picked) {
        lines.add(BuilderLine(lineForDeliverable(t, rate), t, existing: true));
      }
    });
  }

  Future<void> _newItem() async {
    final it = await editLineSheet(context);
    if (it == null || !mounted) return;
    final name = it.desc.split('\n').first;
    setState(() => lines.add(BuilderLine(it, Todo(text: name, hours: it.unit == 'h' ? Todo.fmtHours(it.qty) : ''))));
  }

  Future<void> _edit(BuilderLine l) async {
    final it = await editLineSheet(context, item: l.item);
    if (it == null || !mounted) return;
    setState(() => l.item
      ..desc = it.desc
      ..qty = it.qty
      ..unit = it.unit
      ..rate = it.rate);
  }

  void _create() {
    final s = context.read<Store>();
    setState(() => tried = true);
    if (s.client(clientId) == null) {
      toast(context, 'Choose a client');
      return;
    }
    if (lines.isEmpty) {
      toast(context, 'Add at least one item');
      return;
    }
    final link = projectId.isNotEmpty && s.project(projectId) != null;
    for (final l in lines) {
      l.item.todoId = (l.existing || (link && addToProject)) ? l.part.id : null;
    }
    if (link && addToProject) s.addTodos(projectId, [for (final l in lines) if (!l.existing) l.part]);
    final doc = s.newDoc('quote', clientId: clientId, projectId: link ? projectId : null)
      ..template = template
      ..title = title.text.trim()
      ..items = [for (final l in lines) l.item]
      ..taxPct = _num(taxCtl.text) ?? 0
      ..discount = _num(discountCtl.text) ?? 0
      ..due = DateTime.now().add(Duration(days: validity))
      ..terms = payTerms
      ..sections = buildQuoteSections(_spec(s))
      ..schedule = schedulePresets.firstWhere((p) => p.id == planId).build();
    s.putDoc(doc);
    toast(context, '${doc.number} created');
    Navigator.pushReplacement(context, zoom(DocDetailPage(doc.id)));
  }

  Widget _choices(List<String> labels, int selected, ValueChanged<int> onTap) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (i, l) in labels.indexed) ChoicePill(l, selected: i == selected, onTap: () => onTap(i)),
      ]);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final cur = s.profile.currency;
    final draft = _draft();
    final sections = buildQuoteSections(_spec(s));
    final project = s.project(projectId);
    final aiNote = Ai.ready ? 'Uses your on-device model, so it takes a little while.' : 'No AI model installed: only priced lines in your text are read.';
    return Screen(
      title: 'New quotation',
      bottom: _bottomBar('TOTAL', money(draft.total), 'Create quotation', _create, key: const Key('quote-create')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
        children: [
          builderCard('1 · Template', TemplatePicker(kind: 'quote', selected: template, onChanged: _setTemplate)),
          builderCard(
            '2 · Client',
            _ClientProject(
              clientId: clientId,
              projectId: projectId,
              error: tried && s.client(clientId) == null ? 'Choose a client' : null,
              onClient: (v) => setState(() {
                clientId = v;
                projectId = '';
              }),
              onProject: (v) => setState(() => projectId = v),
              onNewClient: () async {
                final id = await _newClient(context);
                if (id != null && mounted) setState(() => clientId = id);
              },
            ),
          ),
          builderCard(
            '3 · Describe the job',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(key: const Key('quote-title'), controller: title, textCapitalization: TextCapitalization.sentences, decoration: _dec('Title, e.g. Staff management CRM')),
              const SizedBox(height: 10),
              TextField(
                key: const Key('quote-brief'),
                controller: brief,
                minLines: 4,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: _dec('Write it the way you would tell a friend: what the client needs, who it is for, anything that matters. No format needed.'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _action(busy ? 'Writing$progress…' : 'Generate the quotation', Icons.auto_awesome_rounded, busy ? null : _generate, key: const Key('quote-generate'), dark: true)),
              ]),
              const SizedBox(height: 6),
              Text('Writes the items, scope, features, timeline and payment plan. $aiNote', style: const TextStyle(fontSize: 11.5, color: C.muted, height: 1.35)),
            ]),
          ),
          builderCard(
            '4 · Items',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Lines(
                lines: lines,
                emptyText: 'Nothing yet. Generate from your description, add from the project\'s deliverables, or add an item by hand.',
                onEdit: _edit,
                onRemove: (l) => setState(() => lines.remove(l)),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _action('From deliverables', Icons.checklist_rounded, _fromDeliverables, key: const Key('quote-from-deliverables')),
                _action('New item', Icons.add_rounded, _newItem, key: const Key('quote-new-item')),
              ]),
              if (project != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('Also add new items to the project\'s deliverables', style: const TextStyle(fontSize: 12.5, color: C.muted))),
                  Switch(key: const Key('quote-add-to-project'), value: addToProject, activeThumbColor: Colors.white, activeTrackColor: C.green, onChanged: (v) => setState(() => addToProject = v)),
                ]),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(key: const Key('quote-tax'), controller: taxCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: _dec('Tax %'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(key: const Key('quote-discount'), controller: discountCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: _dec('Discount %'))),
              ]),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: Text('Subtotal ${money(draft.subtotal)} · Total ${money(draft.total)} ($cur)', style: mono(12, color: C.muted))),
            ]),
          ),
          builderCard(
            '5 · Terms and conditions',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              builderLabel('Payment plan'),
              _choices([for (final p in schedulePresets) p.label], schedulePresets.indexWhere((p) => p.id == planId), (i) => setState(() => planId = schedulePresets[i].id)),
              const SizedBox(height: 14),
              builderLabel('Payment due within'),
              _choices(_payTerms, _payTerms.indexOf(payTerms).clamp(0, 3), (i) => setState(() => payTerms = _payTerms[i])),
              const SizedBox(height: 14),
              builderLabel('Quotation valid for'),
              _choices(const ['7 days', '15 days', '30 days', '60 days'], const [7, 15, 30, 60].indexOf(validity), (i) => setState(() => validity = const [7, 15, 30, 60][i])),
              const SizedBox(height: 14),
              builderLabel('Revisions included'),
              _choices(const ['1', '2', '3', '5'], const [1, 2, 3, 5].indexOf(revisions), (i) => setState(() => revisions = const [1, 2, 3, 5][i])),
              const SizedBox(height: 14),
              builderLabel('Late payment charge'),
              _choices(const ['None', '1% a month', '2% a month', '5% a month'], const [0.0, 1.0, 2.0, 5.0].indexOf(late), (i) => setState(() => late = const [0.0, 1.0, 2.0, 5.0][i])),
              const SizedBox(height: 14),
              builderLabel('Clauses to include'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in clauseLibrary)
                  ChoicePill(c.title, check: true, selected: clauses.contains(c.id), onTap: () => setState(() => clauses.contains(c.id) ? clauses.remove(c.id) : clauses.add(c.id))),
              ]),
              const SizedBox(height: 10),
              const Text('Standard wording for common freelance jobs, not legal advice. Have a lawyer check it for large contracts. You can edit every section afterwards.',
                  style: TextStyle(fontSize: 11.5, color: C.muted, height: 1.35)),
            ]),
          ),
          builderCard(
            '6 · What the quotation will say',
            sections.isEmpty
                ? const Text('Describe the job and generate, or switch on clauses above, and the written sections appear here.', style: TextStyle(fontSize: 13, color: C.muted, height: 1.4))
                : Material(
                    type: MaterialType.transparency, // the tiles paint their ink on the nearest Material, not on the card behind them
                    child: Column(children: [
                    for (final sec in sections)
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          key: Key('preview-${sec.title}'),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          title: Text(sec.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [DocBlocksView(sec.body)],
                        ),
                      ),
                  ])),
            hint: sections.isEmpty ? null : '${sections.length} sections, tap to read. They are saved on the quotation and printed after the totals.',
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------------------ invoice

/// Build an invoice: bill a quotation (in full, an advance or a payment step), bill finished project work, or start blank.
class InvoiceBuilderPage extends StatefulWidget {
  final String clientId;
  final String? projectId, quoteId;
  const InvoiceBuilderPage({super.key, this.clientId = '', this.projectId, this.quoteId});

  @override
  State<InvoiceBuilderPage> createState() => _InvoiceBuilderPageState();
}

class _InvoiceBuilderPageState extends State<InvoiceBuilderPage> {
  String template = 'classic';
  late String clientId = widget.clientId, projectId = widget.projectId ?? '', quoteId = widget.quoteId ?? '';
  String source = 'blank'; // 'quote' | 'work' | 'blank'
  String bill = 'full'; // 'full' | 'm<i>' (a payment step of the quotation) | 'p25' | 'p50' | 'custom'
  final customPct = TextEditingController(text: '30');
  late String payTerms;
  double late = 0;
  late final TextEditingController notes, taxCtl; // made in initState: a lazy one would first be built while the page is being disposed
  final discountCtl = TextEditingController(text: '0');
  final lines = <BuilderLine>[];
  bool tried = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<Store>();
    notes = TextEditingController(text: s.profile.terms);
    taxCtl = TextEditingController(text: numText(s.profile.defaultTax));
    payTerms = s.profile.dueDays <= 0 ? 'Due on receipt' : 'Net ${s.profile.dueDays}';
    if (widget.quoteId != null && s.doc(widget.quoteId) != null) {
      final q = s.doc(widget.quoteId)!;
      clientId = q.clientId;
      projectId = q.projectId ?? '';
      source = 'quote';
    } else if (widget.projectId != null && (s.project(widget.projectId)?.todos.isNotEmpty ?? false)) {
      source = 'work';
    } else if (_quotes(s).isNotEmpty) {
      source = 'quote';
    }
    if (source == 'quote' && quoteId.isEmpty && _quotes(s).isNotEmpty) quoteId = _quotes(s).first.id;
  }

  @override
  void dispose() {
    for (final c in [customPct, notes, taxCtl, discountCtl]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Doc> _quotes(Store s) => [for (final d in s.docs) if (!d.isInvoice && d.clientId == clientId && d.status != 'rejected') d];

  Doc? _quote(Store s) => _quotes(s).where((q) => q.id == quoteId).firstOrNull;

  double? _pct(Doc q) {
    if (bill == 'full') return 100;
    if (bill == 'custom') return _num(customPct.text);
    if (bill.startsWith('m')) {
      final i = int.tryParse(bill.substring(1)) ?? -1;
      return i >= 0 && i < q.schedule.length ? q.schedule[i].pct : null;
    }
    return double.tryParse(bill.substring(1));
  }

  String _billLabel(Doc q) {
    final p = _pct(q) ?? 0;
    if (bill.startsWith('m')) {
      final i = int.parse(bill.substring(1));
      return '${q.schedule[i].label} (${numText(p)}%)';
    }
    return bill == 'full' ? 'Full payment' : '${numText(p)}% payment';
  }

  void _onClient(String id) => setState(() {
        clientId = id;
        projectId = '';
        quoteId = '';
        final s = context.read<Store>();
        if (source == 'quote' && _quotes(s).isNotEmpty) quoteId = _quotes(s).first.id;
      });

  Future<void> _fromWork() async {
    if (projectId.isEmpty) {
      toast(context, 'Choose a project first');
      return;
    }
    final rate = context.read<Store>().profile.hourlyRate;
    final picked = await pickDeliverables(context,
        projectId: projectId, used: {for (final l in lines) l.part.id}, preselect: (t) => t.done, confirmLabel: 'Bill');
    if (picked == null || !mounted) return;
    setState(() {
      for (final t in picked) {
        lines.add(BuilderLine(lineForDeliverable(t, rate), t, existing: true));
      }
    });
  }

  Future<void> _newItem() async {
    final it = await editLineSheet(context);
    if (it == null || !mounted) return;
    setState(() => lines.add(BuilderLine(it, Todo(text: it.desc.split('\n').first))));
  }

  Future<void> _edit(BuilderLine l) async {
    final it = await editLineSheet(context, item: l.item);
    if (it == null || !mounted) return;
    setState(() => l.item
      ..desc = it.desc
      ..qty = it.qty
      ..unit = it.unit
      ..rate = it.rate);
  }

  /// What the invoice will total, for the bar at the bottom.
  double _total(Store s) {
    if (source == 'quote') {
      final q = _quote(s);
      final p = q == null ? null : _pct(q);
      return q == null || p == null ? 0 : round2(q.total * p / 100);
    }
    return Doc(kind: 'invoice', items: [for (final l in lines) l.item], taxPct: _num(taxCtl.text) ?? 0, discount: _num(discountCtl.text) ?? 0).total;
  }

  void _finish(Doc inv) {
    final s = context.read<Store>();
    final days = _termDays(payTerms) ?? s.profile.dueDays;
    inv
      ..template = template
      ..terms = payTerms
      ..due = inv.date.add(Duration(days: days))
      ..notes = [notes.text.trim(), if (late > 0) 'Late payments may attract a charge of ${numText(late)}% per month.'].where((x) => x.isNotEmpty).join('\n');
    s.putDoc(inv);
    toast(context, '${inv.number} created');
    Navigator.pushReplacement(context, zoom(DocDetailPage(inv.id)));
  }

  void _create() {
    final s = context.read<Store>();
    setState(() => tried = true);
    if (s.client(clientId) == null) {
      toast(context, 'Choose a client');
      return;
    }
    final pid = projectId.isNotEmpty && s.project(projectId) != null ? projectId : null;
    if (source == 'quote') {
      final q = _quote(s);
      final p = q == null ? null : _pct(q);
      if (q == null) {
        toast(context, 'Choose a quotation to bill');
        return;
      }
      if (p == null || p <= 0 || p > 100) {
        toast(context, 'Enter a share between 1 and 100');
        return;
      }
      if (bill == 'full') {
        final done = s.doc(q.convertedToId);
        if (done != null) {
          toast(context, '${q.number} is already invoiced as ${done.number}. Bill an advance or a step instead.');
          return;
        }
        _finish(s.quoteToInvoice(q)); // copies every line, tax and discount, links the two and marks the quote accepted
        return;
      }
      final inv = s.newDoc('invoice', clientId: clientId, projectId: q.projectId)
        ..title = q.title.isEmpty ? q.number : '${q.title} · ${_billLabel(q)}'
        ..items = [LineItem(desc: '${_billLabel(q)} · against ${q.number}', rate: round2(q.subtotal * p / 100))]
        ..taxPct = q.taxPct
        ..discount = q.discount;
      _finish(inv);
      return;
    }
    if (lines.isEmpty) {
      toast(context, 'Add at least one item');
      return;
    }
    final inv = s.newDoc('invoice', clientId: clientId, projectId: pid)
      ..items = [for (final l in lines) l.item]
      ..taxPct = _num(taxCtl.text) ?? 0
      ..discount = _num(discountCtl.text) ?? 0;
    _finish(inv);
  }

  Widget _choices(List<String> labels, int selected, ValueChanged<int> onTap) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (i, l) in labels.indexed) ChoicePill(l, selected: i == selected, onTap: () => onTap(i)),
      ]);

  Widget _quoteSource(Store s) {
    final quotes = _quotes(s);
    if (s.client(clientId) == null) return const Text('Choose a client to see their quotations.', style: TextStyle(fontSize: 13, color: C.muted));
    if (quotes.isEmpty) return const Text('This client has no quotations to bill. Use project work or start blank.', style: TextStyle(fontSize: 13, color: C.muted, height: 1.4));
    final q = _quote(s);
    final converted = q == null ? null : s.doc(q.convertedToId);
    final options = <(String, String)>[
      ('full', 'Full amount'),
      if (q != null && q.schedule.isNotEmpty)
        for (final (i, m) in q.schedule.indexed) ('m$i', '${m.label} · ${numText(m.pct)}%')
      else ...[('p25', '25% advance'), ('p50', '50% advance')],
      ('custom', 'Other %'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        key: ValueKey('quote-$clientId-$quoteId'),
        initialValue: q?.id,
        isExpanded: true,
        decoration: _dec(''),
        items: [
          for (final d in quotes) DropdownMenuItem(value: d.id, child: Text('${d.number} · ${d.title.isEmpty ? 'Untitled' : d.title} · ${money(d.total)}', maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() {
          quoteId = v ?? '';
          bill = 'full';
        }),
      ),
      if (q != null) ...[
        const SizedBox(height: 12),
        builderLabel('Bill'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, label) in options) ChoicePill(label, selected: bill == k, onTap: () => setState(() => bill = k)),
        ]),
        if (bill == 'custom') ...[
          const SizedBox(height: 10),
          TextField(key: const Key('invoice-custom-pct'), controller: customPct, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: _dec('Share of the quotation, %')),
        ],
        const SizedBox(height: 10),
        if (converted != null && bill == 'full')
          Text('${q.number} is already invoiced as ${converted.number}. Pick an advance or a step to bill part of it.', style: const TextStyle(fontSize: 12.5, color: C.redText, height: 1.35))
        else
          Text(
            'Invoice total ${money(_total(s))} of the quotation\'s ${money(q.total)}.${bill == 'full' ? ' Copies every line, tax and discount.' : ' One line for this share, with the quotation\'s tax and discount.'}',
            style: const TextStyle(fontSize: 12.5, color: C.muted, height: 1.35),
          ),
      ],
    ]);
  }

  Widget _itemsSource(Store s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Lines(
          lines: lines,
          emptyText: source == 'work'
              ? 'Pick the project deliverables to bill. The finished ones are ticked for you.'
              : 'Add the items you are billing for.',
          onEdit: _edit,
          onRemove: (l) => setState(() => lines.remove(l)),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (source == 'work') _action('From deliverables', Icons.checklist_rounded, _fromWork, key: const Key('invoice-from-deliverables')),
          _action('New item', Icons.add_rounded, _newItem, key: const Key('invoice-new-item')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(key: const Key('invoice-tax'), controller: taxCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: _dec('Tax %'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(key: const Key('invoice-discount'), controller: discountCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: _dec('Discount %'))),
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final sources = const [('quote', 'From a quotation'), ('work', 'Project work'), ('blank', 'Blank')];
    return Screen(
      title: 'New invoice',
      bottom: _bottomBar('INVOICE TOTAL', money(_total(s)), 'Create invoice', _create, key: const Key('invoice-create')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
        children: [
          builderCard('1 · Template', TemplatePicker(kind: 'invoice', selected: template, onChanged: (v) => setState(() => template = v))),
          builderCard(
            '2 · Client',
            _ClientProject(
              clientId: clientId,
              projectId: projectId,
              error: tried && s.client(clientId) == null ? 'Choose a client' : null,
              onClient: _onClient,
              onProject: (v) => setState(() => projectId = v),
              onNewClient: () async {
                final id = await _newClient(context);
                if (id != null && mounted) _onClient(id);
              },
            ),
          ),
          builderCard(
            '3 · What are you billing?',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (k, label) in sources)
                  ChoicePill(label, selected: source == k, onTap: () => setState(() {
                        source = k;
                        if (k == 'quote' && quoteId.isEmpty && _quotes(s).isNotEmpty) quoteId = _quotes(s).first.id;
                      })),
              ]),
              const SizedBox(height: 14),
              if (source == 'quote') _quoteSource(s) else _itemsSource(s),
            ]),
          ),
          builderCard(
            '4 · Payment',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              builderLabel('Due'),
              _choices(_payTerms, _payTerms.indexOf(payTerms).clamp(0, 3), (i) => setState(() => payTerms = _payTerms[i])),
              const SizedBox(height: 14),
              builderLabel('Late payment charge'),
              _choices(const ['None', '1% a month', '2% a month', '5% a month'], const [0.0, 1.0, 2.0, 5.0].indexOf(late), (i) => setState(() => late = const [0.0, 1.0, 2.0, 5.0][i])),
              const SizedBox(height: 14),
              builderLabel('Note on the invoice'),
              TextField(key: const Key('invoice-notes'), controller: notes, minLines: 2, maxLines: 5, textCapitalization: TextCapitalization.sentences, decoration: _dec('Thank you for your business.')),
              const SizedBox(height: 8),
              const Text('Your UPI QR code and bank details are added automatically from Settings until the invoice is paid.', style: TextStyle(fontSize: 11.5, color: C.muted, height: 1.35)),
            ]),
          ),
        ],
      ),
    );
  }
}
