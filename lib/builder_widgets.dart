import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models.dart';
import 'templates.dart';
import 'ui.dart';

// Widgets shared by the quotation builder, the invoice builder, the document editor and the document page.

Color _accent(DocTemplate t) => Color(0xFF000000 | t.accent);

/// Section label used by the builders: small, upper-case, mono.
Widget builderLabel(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(t.toUpperCase(), style: mono(10, color: C.dim, letterSpacing: .8)),
    );

/// A titled white card.
Widget builderCard(String title, Widget child, {String? hint, Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 12),
      child: CardContainer(
        padding: const EdgeInsets.all(16),
        radius: 20,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: mono(10, color: C.muted, letterSpacing: .8)),
          if (hint != null) ...[const SizedBox(height: 3), Text(hint, style: const TextStyle(fontSize: 12, color: C.muted, height: 1.35))],
          const SizedBox(height: 10),
          child,
        ]),
      ),
    );

/// A selectable pill (single choice, or a toggle when used in a set).
class ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool check; // show a tick when selected (for multi-select sets)
  const ChoicePill(this.label, {super.key, required this.selected, required this.onTap, this.check = false});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? C.dark : C.card,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: selected ? C.dark : C.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (check && selected) ...[const Icon(Icons.check_rounded, size: 15, color: C.textLight), const SizedBox(width: 5)],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? C.textLight : C.text)),
              ),
            ]),
          ),
        ),
      );
}

// ------------------------------------------------------------------------------------------------------- template picker

/// Horizontal strip of template cards, each with a small drawing of the layout.
class TemplatePicker extends StatelessWidget {
  final String kind, selected; // selected: a template id; '' or unknown = the kind's first template
  final ValueChanged<String> onChanged;
  const TemplatePicker({super.key, required this.kind, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final list = kind == 'invoice' ? invoiceTemplates : quoteTemplates;
    final current = templatesFor(kind, selected).id;
    final k = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0); // the caption under each drawing grows with the text size
    return SizedBox(
      height: 120 + 58 * k,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final t = list[i];
          final on = t.id == current;
          return Semantics(
            button: true,
            selected: on,
            label: '${t.name} template. ${t.blurb}',
            excludeSemantics: true,
            child: Pressable(
              onTap: () => onChanged(t.id),
              child: SizedBox(
                key: Key('template-${t.id}'),
                width: 128,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    height: 112,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: on ? C.dark : C.border, width: on ? 2 : 1),
                    ),
                    child: _Thumb(t),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Flexible(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                    if (on) ...[const SizedBox(width: 4), const Icon(Icons.check_circle_rounded, size: 15, color: C.green)],
                  ]),
                  Text(t.blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.muted, height: 1.25)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A tiny drawing of a page in the template's look.
class _Thumb extends StatelessWidget {
  final DocTemplate t;
  const _Thumb(this.t);

  Widget _bar(double w, {Color? color, double h = 4}) =>
      Container(width: w, height: h, decoration: BoxDecoration(color: color ?? C.border, borderRadius: BorderRadius.circular(2)));

  @override
  Widget build(BuildContext context) {
    final a = _accent(t);
    final head = switch (t.look) { 'band' => a, 'minimal' => C.border, _ => C.dark };
    final total = switch (t.look) { 'band' => a, 'minimal' => C.dark, _ => C.dark };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (t.look == 'band')
        Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(color: a, borderRadius: BorderRadius.circular(4)),
          child: Row(children: [_bar(34, color: Colors.white, h: 6), const Spacer(), _bar(22, color: Colors.white54)]),
        )
      else if (t.look == 'minimal')
        Column(children: [
          Row(children: [_bar(30, color: C.dark, h: 5), const Spacer(), _bar(22)]),
          const SizedBox(height: 4),
          Container(height: 1, color: C.dark),
        ])
      else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_bar(38, color: C.dark, h: 7), const SizedBox(height: 3), _bar(18, color: a, h: 3)]),
          const Spacer(),
          _bar(22),
        ]),
      const SizedBox(height: 8),
      Row(children: [_bar(34), const Spacer(), _bar(34)]),
      const SizedBox(height: 7),
      Container(
        height: 9,
        decoration: t.look == 'minimal' ? const BoxDecoration(border: Border(bottom: BorderSide(color: C.dark))) : BoxDecoration(color: head),
      ),
      for (var i = 0; i < 3; i++) ...[
        const SizedBox(height: 4),
        Container(height: 5, color: t.look != 'minimal' && i.isEven ? C.chipLight : Colors.transparent, child: Row(children: [_bar(50), const Spacer(), _bar(14)])),
      ],
      const Spacer(),
      Align(
        alignment: Alignment.centerRight,
        child: t.look == 'minimal'
            ? Container(width: 44, decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.dark))), padding: const EdgeInsets.only(top: 3), child: _bar(26, color: C.dark, h: 4))
            : Container(width: 44, height: 12, decoration: BoxDecoration(color: total, borderRadius: BorderRadius.circular(3))),
      ),
    ]);
  }
}

// ------------------------------------------------------------------------------------------------------- deliverable link

/// A document line made from a project deliverable: its hours at [rate] (or one unit, unpriced, when it has no hours),
/// with its features on a second line, and a link back to the deliverable so the project can show where it was quoted or billed.
LineItem lineForDeliverable(Todo t, double rate) {
  final h = Project(todos: [t]).hoursEstimate;
  final feats = t.sub.map((x) => x.text.trim()).where((x) => x.isNotEmpty).take(6).join(', ');
  return LineItem(
    desc: feats.isEmpty ? t.text.trim() : '${t.text.trim()}\n$feats',
    qty: h > 0 ? h : 1,
    unit: h > 0 ? 'h' : 'x',
    rate: h > 0 ? rate : 0,
    todoId: t.id,
  );
}

/// Sheet to add lines from a project's deliverables: tick any number (or all), or create a new deliverable on the spot.
/// Returns the chosen deliverables, or null when cancelled. Deliverables in [used] are shown as already added.
Future<List<Todo>?> pickDeliverables(BuildContext context,
    {required String projectId, Set<String> used = const {}, bool Function(Todo)? preselect, String confirmLabel = 'Add'}) {
  return showModalBottomSheet<List<Todo>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _DeliverablePicker(projectId, used, preselect, confirmLabel),
  );
}

class _DeliverablePicker extends StatefulWidget {
  final String projectId, confirmLabel;
  final Set<String> used;
  final bool Function(Todo)? preselect;
  const _DeliverablePicker(this.projectId, this.used, this.preselect, this.confirmLabel);

  @override
  State<_DeliverablePicker> createState() => _DeliverablePickerState();
}

class _DeliverablePickerState extends State<_DeliverablePicker> {
  final picked = <String>{};
  final name = TextEditingController(), hours = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    name.dispose();
    hours.dispose();
    super.dispose();
  }

  void _create() {
    final label = name.text.trim();
    if (label.isEmpty) return;
    final h = double.tryParse(hours.text.trim().replaceAll(',', '.')) ?? 0;
    final t = Todo(text: label, hours: Todo.fmtHours(h));
    context.read<Store>().addTodo(widget.projectId, t);
    setState(() {
      picked.add(t.id);
      name.clear();
      hours.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final todos = s.project(widget.projectId)?.todos ?? const <Todo>[];
    if (!_seeded) {
      _seeded = true;
      if (widget.preselect != null) picked.addAll([for (final t in todos) if (!widget.used.contains(t.id) && widget.preselect!(t)) t.id]);
    }
    final free = [for (final t in todos) if (!widget.used.contains(t.id)) t.id];
    final all = free.isNotEmpty && free.every(picked.contains);
    final rate = s.profile.hourlyRate;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
          child: Row(children: [
            Expanded(child: Text('Add from deliverables', style: display(20))),
            if (free.isNotEmpty)
              TextButton(
                key: const Key('pick-all'),
                onPressed: () => setState(() => all ? picked.clear() : picked.addAll(free)),
                child: Text(all ? 'Clear' : 'Select all', style: const TextStyle(fontWeight: FontWeight.w700, color: C.orangeDark)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              rate > 0 ? 'Lines are priced at your hourly rate of ${money(rate)} per hour.' : 'Set your hourly rate in Settings to price these automatically; for now they come in at 0.',
              style: const TextStyle(fontSize: 12, color: C.muted, height: 1.35),
            ),
          ),
        ),
        Flexible(
          child: todos.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('This project has no deliverables yet. Create one below.', style: TextStyle(color: C.muted)))
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final t in todos)
                      _PickRow(
                        key: Key('pick-${t.id}'),
                        todo: t,
                        used: widget.used.contains(t.id),
                        on: picked.contains(t.id),
                        onTap: () => setState(() => picked.contains(t.id) ? picked.remove(t.id) : picked.add(t.id)),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: TextField(
                key: const Key('pick-new-name'),
                controller: name,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: _dec('New deliverable'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('pick-new-hours'),
                controller: hours,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _create(),
                decoration: _dec('Hours'),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const Key('pick-new-add'),
              tooltip: 'Create deliverable',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.add_circle_rounded, color: C.orange, size: 28),
              onPressed: _create,
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          child: Pressable(
            onTap: picked.isEmpty ? null : () => Navigator.pop(context, [for (final t in todos) if (picked.contains(t.id)) t]),
            child: Container(
              key: const Key('pick-confirm'),
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: picked.isEmpty ? C.dimLight : C.dark, borderRadius: BorderRadius.circular(16)),
              child: Text(picked.isEmpty ? 'Tick the deliverables to add' : '${widget.confirmLabel} ${picked.length} ${picked.length == 1 ? 'deliverable' : 'deliverables'}',
                  style: const TextStyle(color: C.textLight, fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PickRow extends StatelessWidget {
  final Todo todo;
  final bool used, on;
  final VoidCallback onTap;
  const _PickRow({super.key, required this.todo, required this.used, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = Project(todos: [todo]).hoursEstimate;
    final sub = [
      if (h > 0) Todo.fmtHours(h),
      if (todo.sub.isNotEmpty) '${todo.sub.length} features',
      if (used) 'already added',
    ].join(' · ');
    return Semantics(
      button: true,
      checked: on || used,
      label: '${todo.text}. $sub',
      excludeSemantics: true,
      child: Pressable(
        onTap: used ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            Icon(used ? Icons.check_box_rounded : (on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
                color: used ? C.dimLight : (on ? C.orange : C.dim), size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(todo.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: used ? C.dim : C.text)),
                if (sub.isNotEmpty) Text(sub, style: mono(11, color: C.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

InputDecoration _dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: C.dim, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      filled: true,
      fillColor: C.bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.dark, width: 1.5)),
    );

// ------------------------------------------------------------------------------------------------------- one line item

/// Sheet to type a new line, or edit one ([item] given). Returns the line, or null when cancelled.
Future<LineItem?> editLineSheet(BuildContext context, {LineItem? item}) => showModalBottomSheet<LineItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _LineSheet(item),
    );

class _LineSheet extends StatefulWidget {
  final LineItem? item;
  const _LineSheet(this.item);
  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  late final desc = TextEditingController(text: widget.item?.desc ?? '');
  late final qty = TextEditingController(text: widget.item == null ? '1' : numText(widget.item!.qty));
  late final unit = TextEditingController(text: widget.item == null || widget.item!.unit == 'x' ? '' : widget.item!.unit);
  late final rate = TextEditingController(text: widget.item == null || widget.item!.rate == 0 ? '' : numText(widget.item!.rate));
  bool tried = false;

  @override
  void dispose() {
    for (final c in [desc, qty, unit, rate]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(String t) => t.trim().isEmpty ? null : double.tryParse(t.trim().replaceAll(',', ''));
  String? get descErr => tried && desc.text.trim().isEmpty ? 'Describe this item' : null;
  String? get qtyErr => tried && ((_num(qty.text) ?? 0) <= 0) ? 'Enter a number above 0' : null;
  String? get rateErr => tried && rate.text.trim().isNotEmpty && (_num(rate.text) == null || _num(rate.text)! < 0) ? 'Enter a number' : null;

  void _save() {
    setState(() => tried = true);
    if (descErr != null || qtyErr != null || rateErr != null) return;
    final base = widget.item;
    Navigator.pop(
        context,
        LineItem(
          desc: desc.text.trim(),
          qty: _num(qty.text)!,
          unit: unit.text.trim().isEmpty ? 'x' : unit.text.trim(),
          rate: _num(rate.text) ?? 0,
          todoId: base?.todoId,
        ));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.item == null ? 'New item' : 'Edit item', style: display(20)),
            const SizedBox(height: 14),
            TextField(
              key: const Key('line-desc'),
              controller: desc,
              autofocus: widget.item == null,
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => tried ? setState(() {}) : null,
              decoration: _dec('What is it? e.g. Staff management module').copyWith(errorText: descErr),
            ),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  key: const Key('line-qty'),
                  controller: qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => tried ? setState(() {}) : null,
                  decoration: _dec('Qty').copyWith(errorText: qtyErr),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: TextField(key: const Key('line-unit'), controller: unit, maxLength: 10, decoration: _dec('Unit (h, pcs…)').copyWith(counterText: ''))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('line-rate'),
                  controller: rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) => _save(),
                  onChanged: (_) => tried ? setState(() {}) : null,
                  decoration: _dec('Rate').copyWith(errorText: rateErr),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Pressable(
              onTap: _save,
              child: Container(
                key: const Key('line-save'),
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(16)),
                child: Text(widget.item == null ? 'Add item' : 'Save item',
                    style: const TextStyle(color: C.textLight, fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ]),
        ),
      );
}

// ------------------------------------------------------------------------------------------------------- reading a document's extras

/// Renders a section body (bullets, tables, paragraphs) on screen.
class DocBlocksView extends StatelessWidget {
  final String body;
  const DocBlocksView(this.body, {super.key});

  @override
  Widget build(BuildContext context) {
    final blocks = parseBlocks(body);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final b in blocks)
        switch (b) {
          ParaBlock() => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(b.text, style: const TextStyle(fontSize: 13, color: C.text, height: 1.4))),
          BulletsBlock() => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final it in b.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(padding: EdgeInsets.only(top: 1), child: Text('•  ', style: TextStyle(fontSize: 13, color: C.muted))),
                      Expanded(child: Text(it, style: const TextStyle(fontSize: 13, color: C.text, height: 1.4))),
                    ]),
                  ),
              ]),
            ),
          TableBlock() => Padding(padding: const EdgeInsets.only(bottom: 8), child: _MiniTable(b)),
        },
    ]);
  }
}

class _MiniTable extends StatelessWidget {
  final TableBlock t;
  const _MiniTable(this.t);

  @override
  Widget build(BuildContext context) {
    final cols = t.header.length;
    List<String> fit(List<String> r) => [...r, ...List.filled((cols - r.length).clamp(0, 99), '')].take(cols).toList();
    TableRow row(List<String> cells, {bool head = false}) => TableRow(
          decoration: BoxDecoration(color: head ? C.chipLight : null, border: const Border(bottom: BorderSide(color: C.borderLight))),
          children: [
            for (final c in fit(cells))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Text(head ? c.toUpperCase() : c,
                    style: head ? mono(9.5, color: C.muted, letterSpacing: .4) : const TextStyle(fontSize: 12, color: C.text, height: 1.3)),
              ),
          ],
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(10)),
        child: Table(
          defaultColumnWidth: const FlexColumnWidth(),
          columnWidths: cols == 3 ? const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(2.2), 2: FlexColumnWidth(1)} : null,
          children: [row(t.header, head: true), for (final r in t.rows) row(r)],
        ),
      ),
    );
  }
}

/// A quotation's payment schedule and sections, as shown on its page.
class DocExtrasView extends StatelessWidget {
  final Doc doc;
  const DocExtrasView(this.doc, {super.key});

  @override
  Widget build(BuildContext context) {
    final sums = scheduleAmounts(doc);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (doc.schedule.isNotEmpty)
        builderCard(
          'Payment schedule',
          Column(children: [
            for (final (i, m) in doc.schedule.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text('${i + 1}. ${m.label}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                  Text('${numText(m.pct)}%', style: mono(12, color: C.muted)),
                  const SizedBox(width: 12),
                  SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: FittedBox(fit: BoxFit.scaleDown, child: Text(money(sums[i]), style: mono(13, color: C.text, weight: FontWeight.w600))))),
                ]),
              ),
          ]),
          key: const Key('doc-schedule'),
        ),
      for (final sec in doc.sections)
        builderCard(sec.title, DocBlocksView(sec.body), key: Key('doc-section-${sec.title}')),
    ]);
  }
}

// ------------------------------------------------------------------------------------------------------- editing a quotation's extras

class _MsCtl {
  final Milestone m;
  final TextEditingController label, pct;
  _MsCtl(this.m)
      : label = TextEditingController(text: m.label),
        pct = TextEditingController(text: numText(m.pct));
  void dispose() {
    label.dispose();
    pct.dispose();
  }
}

class _SecCtl {
  final DocSection s;
  final TextEditingController title, body;
  _SecCtl(this.s)
      : title = TextEditingController(text: s.title),
        body = TextEditingController(text: s.body);
  void dispose() {
    title.dispose();
    body.dispose();
  }
}

/// Edit a quotation's payment schedule and its written sections. Changes go straight into [doc] (the editor's draft).
class QuoteExtrasEditor extends StatefulWidget {
  final Doc doc;
  final VoidCallback onChanged;
  const QuoteExtrasEditor(this.doc, {super.key, required this.onChanged});

  @override
  State<QuoteExtrasEditor> createState() => _QuoteExtrasEditorState();
}

class _QuoteExtrasEditorState extends State<QuoteExtrasEditor> {
  late final List<_MsCtl> ms = [for (final m in widget.doc.schedule) _MsCtl(m)];
  late final List<_SecCtl> secs = [for (final x in widget.doc.sections) _SecCtl(x)];

  @override
  void dispose() {
    for (final c in ms) {
      c.dispose();
    }
    for (final c in secs) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(String t) => double.tryParse(t.trim().replaceAll(',', '')) ?? 0;

  void _changed() {
    for (final c in ms) {
      c.m
        ..label = c.label.text
        ..pct = _num(c.pct.text);
    }
    for (final c in secs) {
      c.s
        ..title = c.title.text
        ..body = c.body.text;
    }
    widget.onChanged();
    setState(() {});
  }

  void _usePreset(SchedulePreset p) {
    for (final c in ms) {
      c.dispose();
    }
    ms.clear();
    widget.doc.schedule
      ..clear()
      ..addAll(p.build());
    ms.addAll([for (final m in widget.doc.schedule) _MsCtl(m)]);
    widget.onChanged();
    setState(() {});
  }

  void _addStep() {
    final m = Milestone('', 0);
    widget.doc.schedule.add(m);
    ms.add(_MsCtl(m));
    widget.onChanged();
    setState(() {});
  }

  void _removeStep(_MsCtl c) {
    widget.doc.schedule.remove(c.m);
    ms.remove(c);
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    widget.onChanged();
    setState(() {});
  }

  void _addSection() {
    final x = DocSection('', '');
    widget.doc.sections.add(x);
    secs.add(_SecCtl(x));
    widget.onChanged();
    setState(() {});
  }

  void _removeSection(_SecCtl c) {
    widget.doc.sections.remove(c.s);
    secs.remove(c);
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    widget.onChanged();
    setState(() {});
  }

  void _moveSection(_SecCtl c, int by) {
    final i = secs.indexOf(c), j = i + by;
    if (j < 0 || j >= secs.length) return;
    secs
      ..removeAt(i)
      ..insert(j, c);
    widget.doc.sections
      ..clear()
      ..addAll([for (final x in secs) x.s]);
    widget.onChanged();
    setState(() {});
  }

  InputDecoration _d(String hint) => InputDecoration(
        hintText: hint,
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
    final total = ms.fold(0.0, (a, c) => a + c.m.pct);
    final sums = scheduleAmounts(widget.doc);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      builderCard(
        'Payment schedule',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in schedulePresets) ChoicePill(p.label, selected: false, onTap: () => _usePreset(p)),
          ]),
          const SizedBox(height: 12),
          for (final (i, c) in ms.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(flex: 3, child: TextField(key: Key('schedule-label-$i'), controller: c.label, onChanged: (_) => _changed(), decoration: _d('When, e.g. On delivery'))),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: Key('schedule-pct-$i'),
                    controller: c.pct,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _changed(),
                    decoration: _d('%').copyWith(suffixText: '%'),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove payment ${i + 1}',
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: const Icon(Icons.close_rounded, color: C.red, size: 20),
                  onPressed: () => _removeStep(c),
                ),
              ]),
            ),
          Row(children: [
            TextButton.icon(
              key: const Key('schedule-add'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: C.orange),
              onPressed: _addStep,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add payment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const Spacer(),
            if (ms.isNotEmpty)
              Flexible(
                child: Text(
                  (total - 100).abs() < .01 ? 'Adds up to 100%' : 'Adds up to ${numText(total)}%, should be 100%',
                  key: const Key('schedule-total'),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: (total - 100).abs() < .01 ? C.greenText : C.redText),
                ),
              ),
          ]),
          if (ms.isNotEmpty) Text('Payments: ${[for (final a in sums) money(a)].join(' · ')}', style: mono(11, color: C.muted)),
        ]),
      ),
      builderCard(
        'Sections',
        hint: 'Scope, timeline and terms printed after the totals. A line starting with - is a bullet; lines like "Name | Detail | 3" make a table.',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, c) in secs.indexed)
            Padding(
              key: ObjectKey(c),
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
                decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.borderLight)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('SECTION ${i + 1}', style: mono(10, color: C.dim, letterSpacing: .8))),
                    IconButton(tooltip: 'Move section ${i + 1} up', constraints: const BoxConstraints(minWidth: 40, minHeight: 40), icon: const Icon(Icons.arrow_upward_rounded, size: 18, color: C.muted), onPressed: i == 0 ? null : () => _moveSection(c, -1)),
                    IconButton(tooltip: 'Move section ${i + 1} down', constraints: const BoxConstraints(minWidth: 40, minHeight: 40), icon: const Icon(Icons.arrow_downward_rounded, size: 18, color: C.muted), onPressed: i == secs.length - 1 ? null : () => _moveSection(c, 1)),
                    IconButton(tooltip: 'Remove section ${i + 1}', constraints: const BoxConstraints(minWidth: 40, minHeight: 40), icon: const Icon(Icons.delete_outline_rounded, size: 20, color: C.red), onPressed: () => _removeSection(c)),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(children: [
                      TextField(key: Key('section-title-$i'), controller: c.title, textCapitalization: TextCapitalization.sentences, onChanged: (_) => _changed(), decoration: _d('Title, e.g. Scope of work').copyWith(fillColor: C.card)),
                      const SizedBox(height: 8),
                      TextField(key: Key('section-body-$i'), controller: c.body, minLines: 3, maxLines: 12, keyboardType: TextInputType.multiline, onChanged: (_) => _changed(), decoration: _d('Text, bullets or a table').copyWith(fillColor: C.card)),
                    ]),
                  ),
                ]),
              ),
            ),
          TextButton.icon(
            key: const Key('section-add'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: C.orange),
            onPressed: _addSection,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add section', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ]),
      ),
    ]);
  }
}
