import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'builders.dart';
import 'client_timeline.dart';
import 'docs.dart';
import 'models.dart';
import 'motion.dart';
import 'projects.dart';
import 'ui.dart';

/// Money figures for one client, always derived from their invoices (never stored).
class ClientLedger {
  final double billed, paid, outstanding, overdue;
  final int invoices, overdueCount;
  const ClientLedger._(this.billed, this.paid, this.outstanding, this.overdue, this.invoices, this.overdueCount);

  factory ClientLedger.of(Store s, String clientId) {
    final inv = s.docs.where((d) => d.clientId == clientId && d.isInvoice).toList();
    double sum(Iterable<Doc> l) => l.fold(0.0, (a, d) => a + d.total);
    final over = inv.where((d) => d.overdue);
    return ClientLedger._(
      sum(inv.where((d) => d.status != 'draft')),
      sum(inv.where((d) => d.status == 'paid')),
      sum(inv.where((d) => d.status == 'sent' || d.status == 'overdue')),
      sum(over),
      inv.length,
      over.length,
    );
  }
}

/// Palette offered for avatars (all from [C]).
const _avatarColors = [C.blue, C.green, C.orange, C.amber, C.red, C.dark];

// ---------------------------------------------------------------------------------------------- list

class ClientsTab extends StatefulWidget {
  const ClientsTab({super.key});
  @override
  State<ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends State<ClientsTab> {
  static const _searchFrom = 6; // show the search box once the list is long enough to need it
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Client c, String q) =>
      [c.name, c.company, c.contact, c.email, c.phone].any((s) => s.toLowerCase().contains(q));

  @override
  Widget build(BuildContext context) {
    final clients = context.watch<Store>().clients;
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty ? clients : clients.where((c) => _matches(c, q)).toList();
    var i = 0;

    return RefreshListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Header(
          'Clients',
          onAdd: () => Navigator.push(context, zoom(ClientEdit(Client(), isNew: true))),
        ).enter(i++),
        if (clients.length >= _searchFrom) ...[
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search clients',
              hintStyle: const TextStyle(color: C.dim, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: C.muted),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded, color: C.muted),
                      onPressed: () => setState(_search.clear),
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              filled: true,
              fillColor: C.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.dark, width: 1.5)),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (clients.isEmpty)
          const EmptyState(Icons.people_outline_rounded, 'No clients yet', 'Tap + to add your first client.')
        else if (shown.isEmpty)
          EmptyState(Icons.search_off_rounded, 'No matches', 'No client matches "${_search.text.trim()}".')
        else
          for (final c in shown) ...[
            _ClientCard(client: c).enter(i++),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _ClientCard extends StatelessWidget {
  final Client client;
  const _ClientCard({required this.client});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final active = s.projects.where((p) => p.clientId == client.id && p.status == 'active').length;
    final ledger = ClientLedger.of(s, client.id);
    final who = [client.contact, client.company].where((x) => x.isNotEmpty).join(' · ');
    final sub = who.isNotEmpty ? who : (client.email.isNotEmpty ? client.email : 'No contact details');

    return CardContainer(
      radius: 20,
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.push(context, zoom(ClientDetailPage(client.id))),
      child: Row(
        children: [
          AvatarSquircle(client.name, initial: client.ini, color: Color(client.colorValue), size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(client.name, style: display(17, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 12, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text('$active active project${active == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (ledger.outstanding > 0) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(ledger.outstanding), style: mono(13, color: C.red, weight: FontWeight.w600)),
                    Text('unpaid', style: mono(10.5, color: C.muted)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------- detail

class ClientDetailPage extends StatelessWidget {
  final String clientId;
  const ClientDetailPage(this.clientId, {super.key});

  Future<void> _delete(BuildContext context, Client c) async {
    final s = context.read<Store>();
    final nDocs = s.docs.where((d) => d.clientId == c.id).length;
    final nProj = s.projects.where((p) => p.clientId == c.id).length;
    if (nDocs > 0) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: C.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: C.border)),
          title: Text("Can't delete ${c.name}", style: display(20)),
          content: Text(
            '${c.name} still has $nDocs invoice${nDocs == 1 ? '' : 's'} / quote${nDocs == 1 ? '' : 's'}. '
            'Documents are financial records, so they are never deleted automatically.\n\n'
            'Open each document below and either delete it or move it to another client, then delete this client.',
            style: const TextStyle(fontFamily: 'Grotesk', color: C.muted),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK', style: TextStyle(color: C.text, fontWeight: FontWeight.bold)))],
        ),
      );
      return;
    }
    final extra = nProj == 0
        ? ''
        : ' This also deletes its $nProj project${nProj == 1 ? '' : 's'} and all their tasks.';
    if (!await confirm(context, 'Delete ${c.name}?', 'This can\'t be undone.$extra')) return;
    if (!context.mounted) return;
    if (s.deleteClient(c.id)) {
      toast(context, 'Deleted ${c.name}');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final c = s.client(clientId);
    if (c == null) {
      return const Screen(
        title: 'Client',
        body: EmptyState(Icons.person_off_outlined, 'Client not found', 'It may have been deleted.'),
      );
    }

    final ledger = ClientLedger.of(s, c.id);
    final projects = s.projects.where((p) => p.clientId == c.id).toList();
    final docs = s.docs.where((d) => d.clientId == c.id).toList()..sort((a, b) => b.date.compareTo(a.date));
    final who = [c.contact, c.company].where((x) => x.isNotEmpty).join(' · ');

    void copy(String label, String v) {
      Clipboard.setData(ClipboardData(text: v));
      toast(context, '$label copied');
    }

    return Screen(
      title: 'Client',
      actions: [
        IconButton(
          tooltip: 'Client timeline',
          icon: const Icon(Icons.timeline_rounded, color: C.text),
          onPressed: () => Navigator.push(context, zoom(ClientTimelinePage(initialClientId: c.id))),
        ),
        IconButton(
          tooltip: 'Edit client',
          icon: const Icon(Icons.edit_outlined, color: C.text),
          onPressed: () => Navigator.push(context, zoom(ClientEdit(c.copy()))),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Row(
            children: [
              AvatarSquircle(c.name, initial: c.ini, color: Color(c.colorValue), size: 62),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: display(24), maxLines: 3, overflow: TextOverflow.ellipsis),
                    if (who.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(who, style: const TextStyle(fontSize: 13, color: C.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
            ],
          ).enter(0),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _Stat('BILLED', ledger.billed, dark: true)),
            const SizedBox(width: 10),
            Expanded(child: _Stat('PAID', ledger.paid, color: C.greenText)),
          ]).enter(1),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _Stat('OUTSTANDING', ledger.outstanding, color: ledger.outstanding > 0 ? C.text : C.dim)),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat('OVERDUE', ledger.overdue,
                  color: ledger.overdue > 0 ? C.red : C.dim, note: ledger.overdueCount > 0 ? '${ledger.overdueCount} invoice${ledger.overdueCount == 1 ? '' : 's'}' : null),
            ),
          ]).enter(2),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Action('+ Project', C.orange, Colors.white, () => newProject(context, c.id)),
              _Action('+ Invoice', C.dark, C.textLight,
                  () => Navigator.push(context, zoom(InvoiceBuilderPage(clientId: c.id)))),
              _Action('+ Quote', C.chipBg, C.text,
                  () => Navigator.push(context, zoom(QuoteBuilderPage(clientId: c.id)))),
            ],
          ).enter(3),
          const Section('Contact'),
          CardContainer(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            radius: 18,
            child: (c.email.isEmpty && c.phone.isEmpty && c.address.isEmpty && c.gstin.isEmpty && c.notes.isEmpty)
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('No contact details yet. Tap the pencil to add them.', style: TextStyle(color: C.muted)),
                  )
                : Column(
                    children: [
                      if (c.email.isNotEmpty) _InfoRow('Email', c.email, onCopy: () => copy('Email', c.email)),
                      if (c.phone.isNotEmpty) _InfoRow('Phone', c.phone, onCopy: () => copy('Phone', c.phone)),
                      if (c.address.isNotEmpty) _InfoRow('Address', c.address),
                      if (c.gstin.isNotEmpty) _InfoRow('Tax ID', c.gstin, onCopy: () => copy('Tax ID', c.gstin)),
                      if (c.notes.isNotEmpty) _InfoRow('Notes', c.notes),
                    ],
                  ),
          ),
          Section('Projects (${projects.length})'),
          CardContainer(
            padding: EdgeInsets.zero,
            radius: 18,
            child: projects.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('No projects for this client yet.', style: TextStyle(color: C.muted))),
                  )
                : Column(
                    children: [
                      for (var k = 0; k < projects.length; k++) ...[
                        if (k > 0) const Divider(height: 1, thickness: 1, color: C.borderLight),
                        Pressable(
                          onTap: () => Navigator.push(context, zoom(ProjectDetailPage(projects[k].id))),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(projects[k].name.isEmpty ? 'Untitled project' : projects[k].name,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(
                                        projects[k].totalTasksCount == 0
                                            ? 'No tasks yet'
                                            : '${projects[k].doneTasksCount}/${projects[k].totalTasksCount} tasks · ${(projects[k].progress * 100).round()}%',
                                        style: mono(11, color: C.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StatusPill(projects[k].status),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          Section('Documents (${docs.length})'),
          CardContainer(
            padding: EdgeInsets.zero,
            radius: 18,
            child: docs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('No invoices or quotes yet.', style: TextStyle(color: C.muted))),
                  )
                : Column(
                    children: [
                      for (var k = 0; k < docs.length; k++) ...[
                        if (k > 0) const Divider(height: 1, thickness: 1, color: C.borderLight),
                        Pressable(
                          onTap: () => Navigator.push(context, zoom(DocDetailPage(docs[k].id))),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${docs[k].number} · ${fmtDate(docs[k].date)}',
                                          style: mono(11, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 1),
                                      Text(docs[k].title.isEmpty ? (docs[k].isInvoice ? 'Invoice' : 'Quote') : docs[k].title,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 120),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(money(docs[k].total), style: mono(13))),
                                      const SizedBox(height: 3),
                                      StatusPill(docs[k].shownStatus),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          Pressable(
            onTap: () => _delete(context, c),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: C.redBorder),
                color: C.redLight,
              ),
              child: const Text('Delete client', style: TextStyle(color: C.redText, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final double value;
  final bool dark;
  final Color color;
  final String? note;
  const _Stat(this.label, this.value, {this.dark = false, this.color = C.text, this.note});

  @override
  Widget build(BuildContext context) => CardContainer(
        color: dark ? C.dark : null,
        borderColor: dark ? C.dark : null,
        radius: 18,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(label, style: mono(10, color: dark ? C.dimLight : C.muted, letterSpacing: .6))),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(value), style: display(22, color: dark ? C.textLight : color)),
            ),
            if (note != null) Text(note!, style: mono(10.5, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

class _Action extends StatelessWidget {
  final String label;
  final Color bg, fg;
  final VoidCallback onTap;
  const _Action(this.label, this.bg, this.fg, this.onTap);

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46, minWidth: 96),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
          child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13.5)),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final VoidCallback? onCopy;
  const _InfoRow(this.label, this.value, {this.onCopy});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(), style: mono(10, color: C.muted, letterSpacing: .8)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 14.5, color: C.text), maxLines: 6, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onCopy != null)
              IconButton(
                tooltip: 'Copy ${label.toLowerCase()}',
                icon: const Icon(Icons.copy_rounded, size: 18, color: C.muted),
                onPressed: onCopy,
              )
            else
              const SizedBox(height: 44),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------------------------- edit

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

class ClientEdit extends StatefulWidget {
  final Client client;
  final bool isNew;
  const ClientEdit(this.client, {super.key, this.isNew = false});

  @override
  State<ClientEdit> createState() => _ClientEditState();
}

class _ClientEditState extends State<ClientEdit> {
  late final c = widget.client.copy(); // draft; committed with one putClient on Save
  final _form = GlobalKey<FormState>();
  bool _tried = false;

  String? _name(String? v) {
    final n = (v ?? '').trim();
    if (n.isEmpty) return 'Enter a client name';
    final dup = context.read<Store>().clients.any((x) => x.id != c.id && x.name.trim().toLowerCase() == n.toLowerCase());
    return dup ? 'A client named "$n" already exists' : null;
  }

  String? _email(String? v) {
    final e = (v ?? '').trim();
    return e.isEmpty || _emailRe.hasMatch(e) ? null : 'Enter a valid email, like name@company.com';
  }

  String? _phone(String? v) {
    final p = (v ?? '').trim();
    if (p.isEmpty) return null;
    return p.replaceAll(RegExp(r'\D'), '').length >= 5 ? null : 'Enter a valid phone number';
  }

  void _save() {
    setState(() => _tried = true);
    if (!_form.currentState!.validate()) {
      final first = [_name(c.name), _email(c.email), _phone(c.phone)].whereType<String>().firstOrNull;
      toast(context, first ?? 'Please fix the highlighted fields');
      return;
    }
    c
      ..name = c.name.trim()
      ..contact = c.contact.trim()
      ..email = c.email.trim()
      ..phone = c.phone.trim()
      ..address = c.address.trim()
      ..gstin = c.gstin.trim()
      ..notes = c.notes.trim()
      ..initial = c.initial.trim().toUpperCase();
    context.read<Store>().putClient(c);
    Navigator.pop(context, c);
  }

  Widget _f(String label, String initial, ValueChanged<String> on,
          {String? Function(String?)? validator,
          TextInputType? keyboard,
          int maxLines = 1,
          String? hint,
          TextCapitalization caps = TextCapitalization.none,
          List<TextInputFormatter>? formatters,
          bool last = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: mono(10, color: C.muted, letterSpacing: .8)),
            const SizedBox(height: 4),
            TextFormField(
              initialValue: initial,
              onChanged: (v) {
                on(v);
                if (_tried) setState(() {});
              },
              validator: validator,
              autovalidateMode: _tried ? AutovalidateMode.always : AutovalidateMode.disabled,
              keyboardType: keyboard ?? (maxLines > 1 ? TextInputType.multiline : null),
              textInputAction: maxLines > 1 ? TextInputAction.newline : (last ? TextInputAction.done : TextInputAction.next),
              textCapitalization: caps,
              inputFormatters: formatters,
              maxLines: maxLines,
              minLines: 1,
              style: const TextStyle(fontFamily: 'Grotesk', fontSize: 15, color: C.text),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: C.dim, fontSize: 14),
                errorMaxLines: 3,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                fillColor: C.card,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.dark, width: 1.5)),
                errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.red)),
                focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.red, width: 1.5)),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Screen(
      title: widget.isNew ? 'New client' : 'Edit client',
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AvatarSquircle(c.name, initial: c.ini, color: Color(c.colorValue), size: 56),
            ),
            const SizedBox(height: 14),
            _f('Client / business name *', c.name, (v) {
              c.name = v;
              setState(() {}); // live avatar letter
            },
                validator: _name, caps: TextCapitalization.words, hint: 'e.g. Northwind Studio'),
            _f('Contact person', c.contact, (v) => c.contact = v, caps: TextCapitalization.words, hint: 'Optional'),
            _f('Email', c.email, (v) => c.email = v, validator: _email, keyboard: TextInputType.emailAddress, hint: 'name@company.com'),
            _f('Phone', c.phone, (v) => c.phone = v,
                validator: _phone,
                keyboard: TextInputType.phone,
                hint: '+91 98765 43210',
                formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-().\s]'))]),
            _f('Address', c.address, (v) => c.address = v, maxLines: 3, caps: TextCapitalization.sentences, hint: 'Shown on their invoices'),
            _f('Tax ID', c.gstin, (v) => c.gstin = v, caps: TextCapitalization.characters, hint: 'Optional'),
            _f('Notes', c.notes, (v) => c.notes = v, maxLines: 4, caps: TextCapitalization.sentences, hint: 'Private, never printed on documents'),
            _f('Avatar letter (optional)', c.initial, (v) {
              c.initial = v;
              setState(() {});
            },
                caps: TextCapitalization.characters,
                hint: 'Defaults to the first letter of the name',
                formatters: [LengthLimitingTextInputFormatter(2)],
                last: true),
            const SizedBox(height: 4),
            Text('AVATAR COLOR', style: mono(10, color: C.muted, letterSpacing: .8)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final col in _avatarColors)
                  Semantics(
                    button: true,
                    selected: c.colorValue == col.toARGB32(),
                    label: 'Avatar color ${_avatarColors.indexOf(col) + 1}',
                    child: Pressable(
                      onTap: () => setState(() => c.colorValue = col.toARGB32()),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.colorValue == col.toARGB32() ? C.orange : Colors.transparent, width: 3),
                            ),
                            child: c.colorValue == col.toARGB32() ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      bottom: Pressable(
        onTap: _save,
        child: Container(
          width: double.infinity,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(16)),
          child: Text(widget.isNew ? 'Create client' : 'Save changes',
              style: const TextStyle(color: C.textLight, fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    );
  }
}
