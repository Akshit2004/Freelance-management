import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'builder_widgets.dart';
import 'builders.dart';
import 'clients.dart';
import 'models.dart';
import 'motion.dart';
import 'pdf.dart';
import 'templates.dart';
import 'ui.dart';

// ---------------------------------------------------------------- shared helpers

String _kindLabel(Doc d) => d.isInvoice ? 'Invoice' : 'Quotation';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days past the due date (0 if due today or not yet due).
int daysOverdue(Doc d) {
  final n = _day(DateTime.now()).difference(_day(d.due)).inDays;
  return n < 0 ? 0 : n;
}

/// 2 -> "2", 1.5 -> "1.5", 0.333 -> "0.33" (quantities and percents; money goes through [money]).
String numLabel(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// A quote that already produced an invoice is frozen: its status can't be changed any more.
bool _locked(Doc d, Store s) => !d.isInvoice && s.doc(d.convertedToId) != null;

/// The statuses a document may move to from where it is. 'overdue' is never one of them: it is derived
/// from "sent" and a past due date, and an invoice leaves it by being paid.
List<String> nextStatuses(Doc d, Store s) {
  if (_locked(d, s)) return const [];
  if (d.isInvoice) {
    return switch (d.status) {
      'draft' => ['sent', 'paid'],
      'sent' => ['paid', 'draft'],
      'paid' => ['sent'],
      _ => ['paid', 'sent'], // legacy stored 'overdue'
    };
  }
  return switch (d.status) {
    'draft' => ['sent'],
    'sent' => ['accepted', 'rejected', 'draft'],
    'accepted' => ['sent'],
    'rejected' => ['sent', 'draft'],
    _ => ['draft'],
  };
}

/// The one obvious forward step (shown as the main button); null when there is none.
String? primaryStatus(Doc d, Store s) {
  if (_locked(d, s)) return null;
  return switch ((d.isInvoice, d.status)) {
    (_, 'draft') => 'sent',
    (true, 'sent' || 'overdue') => 'paid',
    (false, 'sent') => 'accepted',
    _ => null,
  };
}

String statusActionLabel(Doc d, String to) => switch (to) {
      'sent' => d.status == 'draft' ? 'Mark as sent' : 'Move back to sent',
      'paid' => 'Record payment',
      'accepted' => 'Mark as accepted',
      'rejected' => 'Mark as rejected',
      _ => 'Move back to draft',
    };

/// Hook so tests can fake the OS share sheet.
Future<ShareResult> Function(ShareParams) docShare = (p) => SharePlus.instance.share(p);

/// Builds the PDF (or reuses [bytes]), opens the share sheet and, only if the user really picked a target,
/// moves a draft to "sent". Returns true when it was shared.
Future<bool> shareDocPdf(BuildContext context, String docId, {Uint8List? bytes}) async {
  final s = context.read<Store>();
  final doc = s.doc(docId);
  if (doc == null) return false;
  final name = pdfFileName(doc);
  try {
    bytes ??= await buildPdf(doc);
    final res = await docShare(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
      fileNameOverrides: [name],
      subject: '${_kindLabel(doc)} ${doc.number}',
    ));
    if (!context.mounted) return false;
    final cur = s.doc(docId);
    final wasDraft = cur != null && cur.status == 'draft';
    switch (res.status) {
      case ShareResultStatus.success:
        if (wasDraft) s.setDocStatus(docId, 'sent');
        toast(context, wasDraft ? '${doc.number} shared and marked as sent' : '${doc.number} shared');
        return true;
      case ShareResultStatus.dismissed:
        toast(context, wasDraft ? 'Not shared. ${doc.number} is still a draft.' : 'Sharing cancelled');
        return false;
      case ShareResultStatus.unavailable:
        toast(context, 'Shared ${doc.number}. Mark it as sent once it has gone out.');
        return false;
    }
  } catch (_) {
    if (context.mounted) toast(context, 'Could not share the PDF. Please try again.');
    return false;
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? fill, fg, outline;
  const _Btn(this.label, this.onTap, {super.key, this.icon, this.fill, this.fg, this.outline});

  @override
  Widget build(BuildContext context) {
    final color = fg ?? C.text;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : .5,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(16),
              border: outline == null ? null : Border.all(color: outline!, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center, // no Container.alignment: that would swallow all the height of a bottom bar
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 6)],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 14, color: color)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Label ........ value" row that never overflows: long money values shrink instead.
Widget _kv(String k, String v, {TextStyle? ks, TextStyle? vs}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(child: Text(k, style: ks ?? mono(12.5, color: C.muted), maxLines: 2)),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(v, style: vs ?? mono(12.5, color: C.muted), maxLines: 1),
            ),
          ),
        ],
      ),
    );

// ---------------------------------------------------------------- Docs tab

class DocsTab extends StatefulWidget {
  const DocsTab({super.key});
  @override
  State<DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends State<DocsTab> {
  bool quotes = true; // quotations vs invoices
  String stage = 'All';
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _switch(bool toQuotes) => setState(() {
        quotes = toQuotes;
        stage = 'All';
      });

  void _clear() => setState(() {
        stage = 'All';
        search.clear();
      });

  bool _matches(Doc d, String q, Store s) {
    final hay = [d.number, d.title, s.clientName(d.clientId), d.notes, money(d.total), for (final i in d.items) i.desc].join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  void _create(BuildContext context) => Navigator.push(context, zoom(quotes ? const QuoteBuilderPage() : const InvoiceBuilderPage()));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final noun = quotes ? 'quotation' : 'invoice';
    final all = s.docs.where((d) => d.isInvoice != quotes).toList()
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : b.number.compareTo(a.number);
      });
    final stages = quotes ? const ['Draft', 'Sent', 'Accepted', 'Rejected'] : const ['Draft', 'Sent', 'Paid', 'Overdue'];
    final q = search.text.trim().toLowerCase();
    final shown = [
      for (final d in all)
        if ((stage == 'All' || d.shownStatus == stage.toLowerCase()) && (q.isEmpty || _matches(d, q, s))) d,
    ];
    final filtering = stage != 'All' || q.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    var i = 0;

    return RefreshListView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 28),
      children: [
        Header('Documents', addLabel: 'New $noun', onAdd: () => _create(context)).enter(i++),
        _ModeSwitch(quotes: quotes, onChanged: _switch).enter(i++),
        const SizedBox(height: 12),
        if (all.isNotEmpty) ...[
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text),
            decoration: InputDecoration(
              hintText: 'Search number, client or item',
              hintStyle: const TextStyle(color: C.dim, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: C.muted, size: 20),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded, size: 18, color: C.muted),
                      onPressed: () => setState(search.clear),
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              fillColor: C.card,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.dark, width: 1.5)),
            ),
          ).enter(i++),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final st in stages)
                  _StageChip(
                    label: st,
                    count: all.where((d) => d.shownStatus == st.toLowerCase()).length,
                    sum: all.where((d) => d.shownStatus == st.toLowerCase()).fold(0.0, (a, d) => a + d.total),
                    selected: stage == st,
                    onTap: () => setState(() => stage = stage == st ? 'All' : st),
                  ),
              ],
            ),
          ).enter(i++),
          const SizedBox(height: 14),
        ],
        if (all.isEmpty)
          Column(children: [
            EmptyState(
              Icons.receipt_long_rounded,
              quotes ? 'No quotations yet' : 'No invoices yet',
              quotes
                  ? 'Send a quote first, then turn it into an invoice with one tap.'
                  : 'Create an invoice here, or draft one from rough notes in Magic.',
            ),
            _Btn('New $noun', () => _create(context), icon: Icons.add_rounded, fill: C.dark, fg: C.textLight),
          ]).enter(i++)
        else if (shown.isEmpty)
          Column(children: [
            EmptyState(
              Icons.search_off_rounded,
              q.isNotEmpty ? 'No matches' : 'Nothing ${stage.toLowerCase()}',
              q.isNotEmpty
                  ? 'No $noun matches "${search.text.trim()}"${stage != 'All' ? ' in ${stage.toLowerCase()}' : ''}.'
                  : 'No ${stage.toLowerCase()} ${noun}s right now.',
            ),
            if (filtering) _Btn('Clear filters', _clear, outline: C.dark),
          ])
        else
          for (var idx = 0; idx < shown.length; idx++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: idx < 10 ? _DocTile(shown[idx], s).enter(i++) : _DocTile(shown[idx], s),
            ),
      ],
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  final bool quotes;
  final ValueChanged<bool> onChanged;
  const _ModeSwitch({required this.quotes, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool isQuotes) {
      final on = quotes == isQuotes;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          excludeSemantics: true,
          child: Pressable(
            onTap: () => onChanged(isQuotes),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? C.dark : Colors.transparent, borderRadius: BorderRadius.circular(11)),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Grotesk', fontSize: 13.5, fontWeight: FontWeight.w600, color: on ? C.textLight : C.muted)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: C.chipBg, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [seg('Quotations', true), seg('Invoices', false)]),
    );
  }
}

class _StageChip extends StatelessWidget {
  final String label;
  final int count;
  final double sum;
  final bool selected;
  final VoidCallback onTap;
  const _StageChip({required this.label, required this.count, required this.sum, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = statusStyle(label);
    final fgc = selected ? C.textLight : fg;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label, $count, ${money(sum)}',
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 84, minHeight: 44),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected ? C.dark : bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? C.dark : Colors.transparent),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count', style: display(20, color: fgc, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fgc)),
                const SizedBox(height: 2),
                Text(money(sum), style: mono(10.5, color: selected ? C.textLight.withValues(alpha: .8) : fg.withValues(alpha: .85))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  final Doc doc;
  final Store s;
  const _DocTile(this.doc, this.s);

  @override
  Widget build(BuildContext context) {
    final d = doc;
    final client = s.clientName(d.clientId);
    final title = d.title.trim().isNotEmpty ? d.title.trim() : _kindLabel(d);
    final String? hint = d.overdue
        ? (daysOverdue(d) > 0 ? 'Overdue by ${daysOverdue(d)} ${daysOverdue(d) == 1 ? 'day' : 'days'}' : 'Overdue')
        : d.status == 'sent'
            ? '${d.isInvoice ? 'Due' : 'Valid until'} ${fmtDate(d.due)}'
            : null;
    return Semantics(
      button: true,
      label: '${_kindLabel(d)} ${d.number}, $title, $client, ${money(d.total)}, ${d.shownStatus}',
      excludeSemantics: true,
      child: CardContainer(
        padding: EdgeInsets.zero,
        radius: 18,
        onTap: () => Navigator.push(context, zoom(DocDetailPage(d.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (_, box) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${d.number} · ${fmtDate(d.date)}', style: mono(11, color: C.dim), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: C.text)),
                      const SizedBox(height: 1),
                      Text(client, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
                      if (hint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(hint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: d.overdue ? C.redText : C.dim)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * .45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(money(d.total), style: mono(14, weight: FontWeight.w600, color: C.text), maxLines: 1),
                      ),
                      const SizedBox(height: 5),
                      StatusPill(d.shownStatus),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Detail

class DocDetailPage extends StatefulWidget {
  final String docId;
  const DocDetailPage(this.docId, {super.key});

  @override
  State<DocDetailPage> createState() => _DocDetailPageState();
}

class _DocDetailPageState extends State<DocDetailPage> {
  bool _busy = false; // a share / convert is in flight
  bool _gone = false; // deleted: render nothing while the route pops

  Future<void> _convert(Doc doc) async {
    if (_busy) return;
    final s = context.read<Store>();
    setState(() => _busy = true);
    final inv = s.quoteToInvoice(doc); // returns the existing invoice if this quote was already converted
    toast(context, '${inv.number} created from ${doc.number}');
    await Navigator.push(context, zoom(DocDetailPage(inv.id)));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setStatus(Doc doc, String to) async {
    final s = context.read<Store>();
    final back = to == 'draft' || doc.status == 'paid' || to == 'rejected';
    if (back) {
      final ok = await confirm(
        context,
        statusActionLabel(doc, to),
        to == 'rejected'
            ? '${doc.number} will be marked as rejected.'
            : doc.status == 'paid'
                ? 'The payment for ${doc.number} will no longer be recorded.'
                : '${doc.number} goes back to draft.',
        verb: 'Confirm',
      );
      if (!ok || !mounted) return;
    }
    s.setDocStatus(doc.id, to);
    if (mounted) toast(context, '${doc.number} marked as $to');
  }

  Future<void> _statusSheet(Doc doc, List<String> options) async {
    final to = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in options)
              ListTile(
                minTileHeight: 52,
                title: Text(statusActionLabel(doc, o), style: const TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w600)),
                trailing: StatusPill(o),
                onTap: () => Navigator.pop(c, o),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (to != null && mounted) await _setStatus(doc, to);
  }

  Future<void> _delete(Doc doc) async {
    final s = context.read<Store>();
    final ok = await confirm(
      context,
      'Delete ${doc.number}?',
      'This ${_kindLabel(doc).toLowerCase()} and its line items will be removed for good.',
    );
    if (!ok || !mounted) return;
    setState(() => _gone = true);
    s.deleteDoc(doc.id);
    Navigator.pop(context);
    toast(context, '${doc.number} deleted');
  }

  Future<void> _send(Doc doc) async {
    if (_busy) return;
    setState(() => _busy = true);
    await shareDocPdf(context, doc.id);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final doc = s.doc(widget.docId);
    if (_gone) return const Scaffold(backgroundColor: C.bg);
    if (doc == null) {
      return const Screen(
        title: 'Document',
        body: Center(child: EmptyState(Icons.search_off_rounded, 'Document not found', 'It may have been deleted.')),
      );
    }

    final client = s.client(doc.clientId);
    final project = s.project(doc.projectId);
    final converted = s.doc(doc.convertedToId);
    final isQuote = !doc.isInvoice;
    final kindLabel = isQuote ? 'QUOTATION' : 'INVOICE';
    final canConvert = isQuote && converted == null && (doc.status == 'sent' || doc.status == 'accepted');
    final primary = primaryStatus(doc, s);
    final options = nextStatuses(doc, s);
    final others = options.where((o) => o != primary).toList();
    final overdueDays = daysOverdue(doc);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Screen(
      title: doc.number,
      actions: [
        IconButton(
          tooltip: 'Delete ${_kindLabel(doc).toLowerCase()}',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.delete_outline_rounded, color: C.red),
          onPressed: () => _delete(doc),
        ),
        const SizedBox(width: 8),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + bottomSafe),
        children: [
          CardContainer(
            radius: 22,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$kindLabel ${doc.number}', style: mono(11, color: C.dim), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(doc.title.trim().isNotEmpty ? doc.title.trim() : '$kindLabel ${doc.number}', style: display(22, weight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(doc.shownStatus),
                    Text(templateOf(doc).name.toUpperCase(), key: const Key('doc-template-name'), style: mono(10, color: C.dim, letterSpacing: .8)),
                    if (doc.overdue && overdueDays > 0)
                      Text('$overdueDays ${overdueDays == 1 ? 'day' : 'days'} past due',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.redText)),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    border: Border.symmetric(horizontal: BorderSide(color: C.dividerDashed)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isQuote ? 'PREPARED FOR' : 'BILLED TO', style: mono(10, color: C.dim, letterSpacing: 0.8)),
                      if (client != null)
                        Semantics(
                          button: true,
                          label: 'Open client ${client.name}',
                          excludeSemantics: true,
                          child: Pressable(
                            onTap: () => Navigator.push(context, zoom(ClientDetailPage(client.id))),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('${client.name} ›',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: C.orange)),
                              ),
                            ),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Unknown client', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: C.muted)),
                        ),
                      if (client != null && client.email.isNotEmpty)
                        Text(client.email, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
                      if (project != null) ...[
                        const SizedBox(height: 10),
                        Text('PROJECT', style: mono(10, color: C.dim, letterSpacing: 0.8)),
                        const SizedBox(height: 3),
                        Text(project.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _meta('ISSUED', fmtDate(doc.date))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _meta(isQuote ? 'VALID UNTIL' : 'DUE', fmtDate(doc.due),
                                sub: !isQuote && doc.terms.trim().isNotEmpty ? doc.terms.trim() : null),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (doc.items.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No line items.', style: TextStyle(color: C.muted))),
                for (final item in doc.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.desc.trim().isEmpty ? 'Untitled item' : item.desc.trim(),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              Text(
                                '${numLabel(item.qty)}${item.unit.trim().isEmpty || item.unit.trim() == 'x' ? '' : ' ${item.unit.trim()}'} × ${money(item.rate)}',
                                style: mono(11, color: C.dim),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(money(item.amount), style: mono(14, weight: FontWeight.w600, color: C.text), maxLines: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: C.dark),
                const SizedBox(height: 10),
                _kv('Subtotal', money(doc.subtotal)),
                if (doc.discount > 0) _kv('Discount (${numLabel(doc.discount)}%)', '−${money(doc.discountAmount)}'),
                if (doc.taxPct > 0) _kv('Tax (${numLabel(doc.taxPct)}%)', money(doc.tax)),
                const SizedBox(height: 6),
                _kv('Total', money(doc.total), ks: display(16, weight: FontWeight.w700), vs: display(24, weight: FontWeight.w700)),
                if (doc.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('NOTES', style: mono(10, color: C.dim, letterSpacing: 0.8)),
                  const SizedBox(height: 3),
                  Text(doc.notes.trim(), style: const TextStyle(fontSize: 13, color: C.muted)),
                ],
              ],
            ),
          ),
          if (doc.schedule.isNotEmpty || doc.sections.isNotEmpty) ...[const SizedBox(height: 14), DocExtrasView(doc)],
          const SizedBox(height: 2),
          if (canConvert)
            Semantics(
              button: true,
              label: 'Convert to invoice',
              excludeSemantics: true,
              child: Pressable(
                onTap: _busy ? null : () => _convert(doc),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(18)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Convert to invoice', style: display(16, color: Colors.white, weight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('Copies all ${doc.items.length} ${doc.items.length == 1 ? 'line' : 'lines'}, tax and discount. No re-entry.',
                                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .95))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          if (converted != null)
            Semantics(
              button: true,
              label: 'Open invoice ${converted.number}',
              excludeSemantics: true,
              child: Pressable(
                onTap: () => Navigator.push(context, zoom(DocDetailPage(converted.id))),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(color: C.greenLight, borderRadius: BorderRadius.circular(16)),
                  child: Text('Invoiced as ${converted.number} ›',
                      style: const TextStyle(color: C.greenText, fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
              ),
            ),
          if (primary != null) ...[
            const SizedBox(height: 10),
            _Btn(statusActionLabel(doc, primary), () => _setStatus(doc, primary), outline: C.dark),
          ],
          if (others.isNotEmpty) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: C.muted),
                onPressed: () => _statusSheet(doc, others),
                child: const Text('Change status', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
      bottom: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: C.dark,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .2), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Expanded(
              child: _Btn('Edit', () => Navigator.push(context, zoom(DocEditor(doc))), fg: C.textLight),
            ),
            Expanded(
              child: _Btn('PDF', () => Navigator.push(context, zoom(DocPdfPage(doc.id))), fg: C.textLight),
            ),
            Expanded(
              flex: 2,
              child: _Btn(_busy ? 'Working…' : (doc.status == 'draft' ? 'Send' : 'Share'), _busy ? null : () => _send(doc),
                  fill: C.orange, fg: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(String k, String v, {String? sub}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: mono(10, color: C.dim, letterSpacing: 0.8)),
          const SizedBox(height: 3),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          if (sub != null) Text(sub, style: const TextStyle(fontSize: 12, color: C.muted)),
        ],
      );
}

// ---------------------------------------------------------------- PDF preview

class DocPdfPage extends StatefulWidget {
  final String docId;
  const DocPdfPage(this.docId, {super.key});

  @override
  State<DocPdfPage> createState() => _DocPdfPageState();
}

class _DocPdfPageState extends State<DocPdfPage> {
  late Future<Uint8List> _bytes = _build();
  bool _busy = false;

  Future<Uint8List> _build() {
    final doc = context.read<Store>().doc(widget.docId);
    if (doc == null) return Future.error('Document not found');
    return buildPdf(doc);
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = context.watch<Store>().doc(widget.docId);
    return Screen(
      title: doc == null ? 'PDF' : '${doc.number}.pdf',
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const EmptyState(Icons.error_outline_rounded, 'Could not build the PDF', 'Something went wrong while drawing the document.'),
                  _Btn('Try again', () => setState(() => _bytes = _build()), outline: C.dark),
                ]),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: C.orange));
          }
          final bytes = snap.data!;
          return Column(
            children: [
              Expanded(
                child: PdfPreview(
                  build: (_) => bytes,
                  useActions: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  pdfFileName: doc == null ? 'document.pdf' : pdfFileName(doc),
                  scrollViewDecoration: const BoxDecoration(color: C.bg),
                  onError: (_, _) => const Center(child: Text('Preview is not available on this device.', style: TextStyle(color: C.muted))),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + MediaQuery.paddingOf(context).bottom),
                child: Row(
                  children: [
                    Expanded(
                      child: _Btn('Print', _busy || doc == null ? null : () => _run(() => _print(doc, bytes)), icon: Icons.print_outlined, outline: C.dark),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Btn('Save', _busy || doc == null ? null : () => _run(() => _save(doc, bytes)), icon: Icons.download_rounded, outline: C.dark),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Btn('Share', _busy || doc == null ? null : () => _run(() => shareDocPdf(context, doc.id, bytes: bytes)),
                          icon: Icons.ios_share_rounded, fill: C.orange, fg: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _print(Doc doc, Uint8List bytes) async {
    try {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: pdfFileName(doc));
    } catch (_) {
      if (mounted) toast(context, 'Could not open the print dialog.');
    }
  }

  Future<void> _save(Doc doc, Uint8List bytes) async {
    final name = pdfFileName(doc);
    try {
      final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'application/pdf', dialogTitle: 'Save PDF');
      if (uri != null && mounted) toast(context, 'Saved $name');
    } catch (_) {
      if (mounted) toast(context, 'Could not save the file.');
    }
  }
}

// ---------------------------------------------------------------- Editor

class _ItemCtl {
  final LineItem item;
  final TextEditingController desc, qty, unit, rate;
  final focus = FocusNode();
  final key = GlobalKey();
  _ItemCtl(this.item)
      : desc = TextEditingController(text: item.desc),
        qty = TextEditingController(text: numText(item.qty)),
        unit = TextEditingController(text: item.unit == 'x' ? '' : item.unit),
        rate = TextEditingController(text: numText(item.rate));

  void dispose() {
    desc.dispose();
    qty.dispose();
    unit.dispose();
    rate.dispose();
    focus.dispose();
  }
}

/// Empty -> 0, "1,200.5" -> 1200.5, garbage -> null.
double? _num(String s) {
  final t = s.replaceAll(',', '').trim();
  if (t.isEmpty) return 0;
  final v = double.tryParse(t);
  return v == null || !v.isFinite ? null : v;
}

const _maxAmount = 1e9;
const _presets = ['Net 7', 'Net 14', 'Net 30', 'Due on receipt'];

/// "Net 14" -> 14, "Due on receipt" -> 0, anything else -> null.
int? _termDays(String terms) {
  final t = terms.trim().toLowerCase();
  if (t == 'due on receipt') return 0;
  final m = RegExp(r'^net\s*(\d{1,3})$').firstMatch(t);
  return m == null ? null : int.parse(m.group(1)!);
}

class DocEditor extends StatefulWidget {
  final Doc doc;
  final bool isNew;
  const DocEditor(this.doc, {super.key, this.isNew = false});

  @override
  State<DocEditor> createState() => _DocEditorState();
}

class _DocEditorState extends State<DocEditor> {
  // The draft: all edits land here and are committed with one putDoc on Save.
  late final Doc d = widget.doc.copy();
  late final String _initial = jsonEncode(d.toJson());
  late final List<_ItemCtl> _items = [for (final i in d.items) _ItemCtl(i)];
  late final title = TextEditingController(text: d.title);
  late final number = TextEditingController(text: d.number);
  late final terms = TextEditingController(text: d.terms);
  late final tax = TextEditingController(text: numText(d.taxPct));
  late final discount = TextEditingController(text: numText(d.discount));
  late final notes = TextEditingController(text: d.notes);
  final _clientKey = GlobalKey(), _numberKey = GlobalKey(), _dueKey = GlobalKey(), _taxKey = GlobalKey(), _itemsKey = GlobalKey();
  bool _submitted = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _initial; // snapshot before any field is touched, for the unsaved-changes check
  }

  @override
  void dispose() {
    for (final c in [title, number, terms, tax, discount, notes, _scroll]) {
      c.dispose();
    }
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  bool get _dirty => jsonEncode(d.toJson()) != _initial;

  // ---- validation (errors only show after the first Save attempt)
  String? _clientErr(Store s) => s.client(d.clientId) == null ? 'Choose a client' : null;

  String? _numberErr(Store s) {
    final n = number.text.trim();
    if (n.isEmpty) return 'Enter a number';
    if (s.docs.any((x) => x.id != d.id && x.number == n)) return 'This number is already used';
    return null;
  }

  String? _dueErr() => _day(d.due).isBefore(_day(d.date)) ? 'Can\'t be before the issue date' : null;

  String? _pctErr(TextEditingController c) {
    final v = _num(c.text);
    return v == null || v < 0 || v > 100 ? 'Enter a number from 0 to 100' : null;
  }

  String? _descErr(_ItemCtl c) => c.desc.text.trim().isEmpty ? 'Describe this item' : null;

  String? _qtyErr(_ItemCtl c) {
    final v = _num(c.qty.text);
    if (v == null) return 'Enter a number';
    if (v <= 0) return 'Must be above 0';
    return v > _maxAmount ? 'Too large' : null;
  }

  String? _rateErr(_ItemCtl c) {
    final v = _num(c.rate.text);
    if (v == null) return 'Enter a number';
    if (v < 0) return 'Can\'t be negative';
    return v > _maxAmount ? 'Too large' : null;
  }

  String? _totalErr() => !d.total.isFinite || d.total > 1e12 ? 'This total is too large' : null;

  String? _e(String? e) => _submitted ? e : null;

  GlobalKey? _firstError(Store s) {
    if (_clientErr(s) != null) return _clientKey;
    if (_numberErr(s) != null) return _numberKey;
    if (_dueErr() != null) return _dueKey;
    if (_pctErr(tax) != null || _pctErr(discount) != null) return _taxKey;
    if (d.items.isEmpty) return _itemsKey;
    for (final c in _items) {
      if (_descErr(c) != null || _qtyErr(c) != null || _rateErr(c) != null) return c.key;
    }
    if (_totalErr() != null) return _itemsKey;
    return null;
  }

  // ---- edits
  void _touch() => setState(() {});

  void _addItem() {
    final c = _ItemCtl(LineItem());
    setState(() {
      d.items.add(c.item);
      _items.add(c);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      c.focus.requestFocus();
      if (c.key.currentContext != null) Scrollable.ensureVisible(c.key.currentContext!, duration: const Duration(milliseconds: 250), alignment: .2);
    });
  }

  void _removeItem(_ItemCtl c) {
    setState(() {
      d.items.remove(c.item);
      _items.remove(c);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose()); // after the field left the tree
  }

  Future<void> _pickDate(bool issue) async {
    final p = await pickDate(context, issue ? d.date : d.due);
    if (p == null || !mounted) return;
    setState(() {
      if (issue) {
        final gap = d.due.difference(d.date); // keep the same payment window when the issue date moves
        d.date = p;
        d.due = p.add(gap.isNegative ? Duration.zero : gap);
      } else {
        d.due = p;
      }
    });
  }

  void _setTerms(String t) {
    d.terms = t;
    final days = _termDays(t);
    if (days != null) d.due = d.date.add(Duration(days: days));
  }

  /// Adds lines made from the project's deliverables (a billed invoice line keeps a link back to its deliverable).
  Future<void> _fromDeliverables() async {
    final pid = d.projectId;
    if (pid == null) return;
    final rate = context.read<Store>().profile.hourlyRate;
    final picked = await pickDeliverables(context,
        projectId: pid, used: {for (final i in d.items) if (i.todoId != null) i.todoId!}, preselect: d.isInvoice ? (t) => t.done : null, confirmLabel: 'Add');
    if (picked == null || !mounted) return;
    setState(() {
      for (final t in picked) {
        final c = _ItemCtl(lineForDeliverable(t, rate));
        d.items.add(c.item);
        _items.add(c);
      }
    });
  }

  Future<void> _newClient() async {
    final created = await Navigator.push<Object?>(context, zoom(ClientEdit(Client(), isNew: true)));
    if (!mounted) return;
    if (created is Client && context.read<Store>().client(created.id) != null) {
      setState(() {
        d.clientId = created.id;
        d.projectId = null;
      });
    }
  }

  Future<void> _save() async {
    final s = context.read<Store>();
    FocusScope.of(context).unfocus();
    setState(() => _submitted = true);
    final bad = _firstError(s);
    if (bad != null) {
      toast(context, 'Please fix the highlighted fields');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = bad.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: .1);
      });
      return;
    }
    d
      ..title = title.text.trim()
      ..number = number.text.trim()
      ..terms = terms.text.trim()
      ..notes = notes.text.trim()
      ..taxPct = _num(tax.text) ?? 0
      ..discount = _num(discount.text) ?? 0;
    for (final c in _items) {
      c.item
        ..desc = c.desc.text.trim()
        ..unit = c.unit.text.trim().isEmpty ? 'x' : c.unit.text.trim()
        ..qty = _num(c.qty.text) ?? 1
        ..rate = _num(c.rate.text) ?? 0;
    }
    s.putDoc(d);
    if (!mounted) return;
    toast(context, widget.isNew ? '${d.number} created' : 'Changes saved');
    if (widget.isNew) {
      Navigator.pushReplacement(context, zoom(DocDetailPage(d.id)));
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _confirmLeave() async {
    final ok = await confirm(context, 'Discard changes?', 'What you entered for this ${d.kind} has not been saved.', verb: 'Discard');
    if (ok && mounted) Navigator.pop(context);
  }

  // ---- widgets
  InputDecoration _dec({String? hint, String? error, String? prefix}) => InputDecoration(
        hintText: hint,
        errorText: error,
        errorMaxLines: 2,
        prefixText: prefix,
        hintStyle: const TextStyle(color: C.dim, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        fillColor: C.card,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.dark, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.red)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.red, width: 1.5)),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t.toUpperCase(), style: mono(10, color: C.dim, letterSpacing: 0.8)),
      );

  Widget _tf(
    String label,
    TextEditingController c, {
    String? hint,
    String? error,
    bool number = false,
    TextInputAction action = TextInputAction.next,
    TextCapitalization cap = TextCapitalization.none,
    int maxLines = 1,
    FocusNode? focus,
    String? prefix,
    int? maxLength,
    Key? key,
  }) =>
      Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(label),
            TextField(
              controller: c,
              focusNode: focus,
              onChanged: (_) => _touch(),
              textInputAction: action,
              textCapitalization: cap,
              keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
              inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null,
              maxLines: maxLines,
              minLines: 1,
              maxLength: maxLength,
              style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text),
              decoration: _dec(hint: hint, error: error, prefix: prefix).copyWith(counterText: ''),
            ),
          ],
        ),
      );

  Widget _dateField(String label, DateTime v, VoidCallback onTap, {String? error, Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(label),
            Semantics(
              button: true,
              label: '$label ${fmtDate(v)}',
              excludeSemantics: true,
              child: Pressable(
                onTap: onTap,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: error == null ? C.border : C.red),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(fmtDate(v), style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text))),
                      const Icon(Icons.calendar_today_rounded, size: 16, color: C.muted),
                    ],
                  ),
                ),
              ),
            ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 4, left: 4), child: Text(error, style: const TextStyle(fontSize: 12, color: C.red))),
          ],
        ),
      );

  Widget _itemCard(int i, _ItemCtl c, String cur) {
    return Padding(
      key: ObjectKey(c),
      padding: const EdgeInsets.only(bottom: 10),
      child: KeyedSubtree(
        key: c.key,
        child: CardContainer(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          radius: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('ITEM ${i + 1}', style: mono(10, color: C.dim, letterSpacing: 0.8))),
                  IconButton(
                    tooltip: 'Remove item ${i + 1}',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.delete_outline_rounded, color: C.red, size: 22),
                    onPressed: () => _removeItem(c),
                  ),
                ],
              ),
              _tf('Description', c.desc,
                  hint: 'e.g. Logo design', error: _e(_descErr(c)), cap: TextCapitalization.sentences, maxLines: 4, focus: c.focus),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _tf('Qty', c.qty, number: true, error: _e(_qtyErr(c)))),
                  const SizedBox(width: 10),
                  Expanded(child: _tf('Unit', c.unit, hint: 'hrs, pcs…', maxLength: 10)),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _tf('Rate ($cur)', c.rate, number: true, error: _e(_rateErr(c)), action: TextInputAction.done)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Amount'),
                        Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(money(c.item.amount), style: mono(14, weight: FontWeight.w600, color: C.text)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    // keep the draft in sync with what is typed, so totals and the dirty check are live
    for (final c in _items) {
      c.item
        ..desc = c.desc.text
        ..qty = _num(c.qty.text) ?? 0
        ..rate = _num(c.rate.text) ?? 0
        ..unit = c.unit.text.trim().isEmpty ? 'x' : c.unit.text.trim();
    }
    d
      ..title = title.text
      ..number = number.text
      ..notes = notes.text
      ..taxPct = _num(tax.text) ?? 0
      ..discount = _num(discount.text) ?? 0;
    if (d.isInvoice) d.terms = terms.text; // quotes carry no payment terms

    final isInv = d.isInvoice;
    final clientValid = s.client(d.clientId) != null;
    final projects = [for (final p in s.projects) if (p.clientId == d.clientId) p];
    final projectValue = projects.any((p) => p.id == d.projectId) ? d.projectId! : '';
    final cur = s.profile.currency;
    final totalErr = _e(_totalErr());
    final noun = isInv ? 'invoice' : 'quotation';
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Screen(
        title: widget.isNew ? 'New $noun' : 'Edit ${d.number}',
        body: ListView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomPad),
          children: [
            if (!widget.isNew && d.status != 'draft')
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.blueLight, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  'This $noun is already ${d.shownStatus}. Changes here will not update a copy your client already has.',
                  style: const TextStyle(fontSize: 12.5, color: C.blueText),
                ),
              ),
            // --- client
            KeyedSubtree(
              key: _clientKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _label('Client')),
                      if (s.clients.isNotEmpty)
                        TextButton(
                          style: TextButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: C.orange, padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: _newClient,
                          child: const Text('+ New client', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                        ),
                    ],
                  ),
                  if (s.clients.isEmpty)
                    CardContainer(
                      radius: 14,
                      borderColor: _submitted ? C.red : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('You need a client to bill first.', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 4),
                          const Text('Add one now and it will be picked for this document.', style: TextStyle(fontSize: 12.5, color: C.muted)),
                          const SizedBox(height: 10),
                          _Btn('Add a client', _newClient, icon: Icons.person_add_alt_1_rounded, fill: C.dark, fg: C.textLight),
                        ],
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('client-${d.clientId}-${s.clients.length}'),
                      initialValue: clientValid ? d.clientId : null,
                      isExpanded: true,
                      hint: const Text('Select a client', style: TextStyle(color: C.dim, fontSize: 14)),
                      items: [
                        for (final c in s.clients)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name.isEmpty ? 'Unnamed client' : c.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text)),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        d.clientId = v ?? '';
                        d.projectId = null;
                      }),
                      decoration: _dec(error: _e(_clientErr(s))),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            if (clientValid && projects.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Project (optional)'),
                    DropdownButtonFormField<String>(
                      key: ValueKey('project-${d.clientId}-$projectValue'),
                      initialValue: projectValue,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(value: '', child: Text('No project', style: TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.muted))),
                        for (final p in projects)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text)),
                          ),
                      ],
                      onChanged: (v) => setState(() => d.projectId = (v == null || v.isEmpty) ? null : v),
                      decoration: _dec(),
                    ),
                  ],
                ),
              ),
            _label('Template'),
            TemplatePicker(kind: d.kind, selected: d.template, onChanged: (v) => setState(() => d.template = v)),
            const SizedBox(height: 14),
            _tf('Title / subject', title, hint: 'e.g. Menu illustrations', cap: TextCapitalization.sentences),
            _tf('Number', number, error: _e(_numberErr(s)), key: _numberKey, maxLength: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _dateField('Issue date', d.date, () => _pickDate(true))),
                const SizedBox(width: 10),
                Expanded(child: _dateField(isInv ? 'Due date' : 'Valid until', d.due, () => _pickDate(false), error: _e(_dueErr()), key: _dueKey)),
              ],
            ),
            if (isInv) ...[
              _label('Payment terms'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _presets)
                    Semantics(
                      button: true,
                      selected: terms.text.trim() == p,
                      label: p,
                      excludeSemantics: true,
                      child: Pressable(
                        onTap: () => setState(() {
                          terms.text = p;
                          _setTerms(p);
                        }),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44, minWidth: 48),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: terms.text.trim() == p ? C.dark : C.chipLight,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(p,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: terms.text.trim() == p ? C.textLight : C.text)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: terms,
                  onChanged: (v) {
                    _setTerms(v);
                    _touch();
                  },
                  textInputAction: TextInputAction.next,
                  maxLength: 60,
                  style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text),
                  decoration: _dec(hint: 'Or write your own, e.g. Net 45').copyWith(counterText: ''),
                ),
              ),
            ],
            Row(
              key: _taxKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _tf('Tax %', tax, number: true, error: _e(_pctErr(tax)), hint: '0')),
                const SizedBox(width: 10),
                Expanded(child: _tf('Discount %', discount, number: true, error: _e(_pctErr(discount)), hint: '0')),
              ],
            ),
            Padding(
              key: _itemsKey,
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text('LINE ITEMS', style: mono(10, color: C.dim, letterSpacing: 0.8))),
                  TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: C.orange),
                    onPressed: _addItem,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add item', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
            ),
            if (d.items.isEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: C.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _submitted ? C.red : C.border),
                ),
                child: Text(_submitted ? 'Add at least one line item.' : 'No items yet. Tap "Add item" to start.',
                    style: TextStyle(fontSize: 13, color: _submitted ? C.red : C.muted)),
              ),
            for (final (i, c) in _items.indexed) _itemCard(i, c, cur),
            _Btn('Add line item', _addItem, icon: Icons.add_rounded, outline: C.border),
            if (d.projectId != null) ...[
              const SizedBox(height: 8),
              _Btn('Add from deliverables', _fromDeliverables, icon: Icons.checklist_rounded, outline: C.border, key: const Key('editor-from-deliverables')),
            ],
            if (!isInv) ...[const SizedBox(height: 18), QuoteExtrasEditor(d, onChanged: _touch)],
            const SizedBox(height: 18),
            _tf('Notes', notes, hint: 'Shown on the PDF, e.g. payment instructions', cap: TextCapitalization.sentences, maxLines: 5, action: TextInputAction.newline),
            CardContainer(
              radius: 16,
              child: Column(
                children: [
                  _kv('Subtotal', money(d.subtotal)),
                  if (d.discount > 0) _kv('Discount (${numLabel(d.discount)}%)', '−${money(d.discountAmount)}'),
                  if (d.taxPct > 0) _kv('Tax (${numLabel(d.taxPct)}%)', money(d.tax)),
                  const Divider(height: 18, color: C.border),
                  _kv('Total ($cur)', money(d.total), ks: display(15, weight: FontWeight.w700), vs: display(22, weight: FontWeight.w700)),
                  if (totalErr != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(totalErr, style: const TextStyle(fontSize: 12, color: C.red))),
                ],
              ),
            ),
          ],
        ),
        bottom: _Btn(widget.isNew ? 'Create $noun' : 'Save changes', _save, fill: C.dark, fg: C.textLight),
      ),
    );
  }
}
