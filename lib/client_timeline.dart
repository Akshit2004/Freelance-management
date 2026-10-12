import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'clients.dart';
import 'docs.dart';
import 'models.dart';
import 'motion.dart';
import 'projects.dart';
import 'ui.dart';

class ClientTimelinePage extends StatefulWidget {
  final String? initialClientId;
  const ClientTimelinePage({super.key, this.initialClientId});

  @override
  State<ClientTimelinePage> createState() => _ClientTimelinePageState();
}

class _ClientTimelinePageState extends State<ClientTimelinePage> {
  String? _selectedClientId;
  String _typeFilter = 'All'; // 'All', 'Work', 'Documents', 'Payments', 'Notes'

  @override
  void initState() {
    super.initState();
    _selectedClientId = widget.initialClientId;
  }

  void _openAddNoteDialog(BuildContext context, String clientId) {
    final noteController = TextEditingController();
    String noteType = 'call';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final inset = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, inset + 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Log Communication', style: display(19))),
                      IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Note type chips
                  Row(
                    children: [
                      for (final t in [
                        ('call', 'Call', Icons.phone_in_talk_rounded),
                        ('meeting', 'Meeting', Icons.groups_rounded),
                        ('email', 'Email', Icons.email_rounded),
                        ('note', 'Note', Icons.edit_note_rounded),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Pressable(
                            onTap: () => setModalState(() => noteType = t.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                              decoration: BoxDecoration(
                                color: noteType == t.$1 ? C.dark : C.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: noteType == t.$1 ? C.dark : C.border),
                              ),
                              child: Row(
                                children: [
                                  Icon(t.$3, size: 14, color: noteType == t.$1 ? C.textLight : C.muted),
                                  const SizedBox(width: 5),
                                  Text(
                                    t.$2,
                                    style: TextStyle(
                                      fontFamily: 'Grotesk',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: noteType == t.$1 ? C.textLight : C.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLines: 4,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13.5, height: 1.4),
                    decoration: InputDecoration(
                      labelText: 'Communication Notes',
                      hintText: 'What was discussed? Decisions, feedback, deadlines agreed...',
                      filled: true,
                      fillColor: C.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Pressable(
                    onTap: () {
                      final text = noteController.text.trim();
                      if (text.isEmpty) {
                        toast(ctx, 'Please enter some notes');
                        return;
                      }
                      context.read<Store>().addTimelineNote(TimelineNote(
                            clientId: clientId,
                            text: text,
                            type: noteType,
                          ));
                      Navigator.pop(ctx);
                      toast(ctx, 'Note recorded in timeline');
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: const Text('Save Note',
                          style: TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 14, color: C.textLight)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final clients = s.clients;

    // Pick first client if not set and clients available
    final clientId = _selectedClientId ?? (clients.isNotEmpty ? clients.first.id : null);
    final client = clientId != null ? s.client(clientId) : null;

    final events = <_TimelineItem>[];

    if (client != null) {
      // 1. Projects
      for (final p in s.projects.where((p) => p.clientId == client.id)) {
        events.add(_TimelineItem(
          date: p.deadline ?? DateTime.now(),
          category: 'Work',
          title: p.name.isEmpty ? 'Untitled project' : p.name,
          subtitle: '${p.status.toUpperCase()} · ${p.doneTasksCount}/${p.totalTasksCount} tasks complete',
          icon: Icons.folder_rounded,
          color: p.status == 'done' ? C.green : C.blue,
          onTap: () => Navigator.push(context, zoom(ProjectDetailPage(p.id))),
        ));
      }

      // 2. Documents
      for (final d in s.docs.where((d) => d.clientId == client.id)) {
        events.add(_TimelineItem(
          date: d.date,
          category: 'Documents',
          title: '${d.number} · ${d.title.isNotEmpty ? d.title : (d.isInvoice ? 'Invoice' : 'Quotation')}',
          subtitle: '${d.shownStatus.toUpperCase()} · ${money(d.total)}',
          icon: d.isInvoice ? Icons.receipt_long_rounded : Icons.request_quote_rounded,
          color: d.isInvoice ? (d.overdue ? C.red : C.blue) : C.orange,
          onTap: () => Navigator.push(context, zoom(DocDetailPage(d.id))),
        ));

        // 3. Payments
        for (final pay in d.payments) {
          events.add(_TimelineItem(
            date: pay.date,
            category: 'Payments',
            title: 'Payment Received: ${money(pay.amount)}',
            subtitle: 'Via ${pay.method} on ${d.number}${pay.reference.isNotEmpty ? ' (Ref: ${pay.reference})' : ''}',
            icon: Icons.check_circle_rounded,
            color: C.green,
            onTap: () => Navigator.push(context, zoom(DocDetailPage(d.id))),
          ));
        }
      }

      // 4. Communication Notes
      for (final n in s.timelineNotesFor(client.id)) {
        final icon = switch (n.type) {
          'call' => Icons.phone_in_talk_rounded,
          'meeting' => Icons.groups_rounded,
          'email' => Icons.email_rounded,
          _ => Icons.edit_note_rounded,
        };
        events.add(_TimelineItem(
          date: n.date,
          category: 'Notes',
          title: '${n.type.toUpperCase()}: ${n.text}',
          subtitle: 'Logged on ${fmtDate(n.date)}',
          icon: icon,
          color: C.dark,
          onDelete: () => s.deleteTimelineNote(n.id),
        ));
      }

      // Sort newest first
      events.sort((a, b) => b.date.compareTo(a.date));
    }

    final filteredEvents = _typeFilter == 'All' ? events : events.where((e) => e.category == _typeFilter).toList();

    var i = 0;

    return Screen(
      title: 'Client Timeline',
      actions: [
        if (client != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Pressable(
              onTap: () => _openAddNoteDialog(context, client.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_comment_rounded, size: 15, color: C.textLight),
                    SizedBox(width: 5),
                    Text('Log Note', style: TextStyle(fontFamily: 'Grotesk', fontSize: 12.5, fontWeight: FontWeight.w700, color: C.textLight)),
                  ],
                ),
              ),
            ),
          ),
      ],
      body: clients.isEmpty
          ? const Center(child: EmptyState(Icons.people_outline_rounded, 'No clients yet', 'Add a client first to view their timeline.'))
          : RefreshListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
              children: [
                // Client Selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: C.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: clientId,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: C.text),
                      items: [
                        for (final c in clients)
                          DropdownMenuItem(
                            value: c.id,
                            child: Row(
                              children: [
                                AvatarSquircle(c.name, color: Color(c.colorValue), size: 28),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    c.name,
                                    style: const TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 14.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (id) => id != null ? setState(() => _selectedClientId = id) : null,
                    ),
                  ),
                ).enter(i++),
                const SizedBox(height: 12),

                // Client Summary Card
                if (client != null) ...[
                  () {
                    final ledger = ClientLedger.of(s, client.id);
                    return CardContainer(
                      color: C.cardDark,
                      borderColor: C.cardDark,
                      radius: 20,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          AvatarSquircle(client.name, color: Color(client.colorValue), size: 48),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(client.name, style: display(17, color: C.textLight), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(
                                  client.company.isNotEmpty ? client.company : (client.email.isNotEmpty ? client.email : 'No contact specified'),
                                  style: const TextStyle(fontSize: 12, color: C.dimLight),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${money(ledger.paid)} paid · ${money(ledger.outstanding)} unpaid',
                                  style: mono(11.5, color: ledger.outstanding > 0 ? C.red : C.greenPaid, weight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios_rounded, color: C.dimLight, size: 16),
                            onPressed: () => Navigator.push(context, zoom(ClientDetailPage(client.id))),
                          ),
                        ],
                      ),
                    );
                  }().enter(i++),
                  const SizedBox(height: 14),

                  // Category Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final cat in ['All', 'Work', 'Documents', 'Payments', 'Notes'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Pressable(
                              onTap: () => setState(() => _typeFilter = cat),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                                decoration: BoxDecoration(
                                  color: _typeFilter == cat ? C.dark : C.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _typeFilter == cat ? C.dark : C.border),
                                ),
                                child: Text(
                                  cat,
                                  style: TextStyle(
                                    fontFamily: 'Grotesk',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: _typeFilter == cat ? C.textLight : C.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ).enter(i++),
                  const SizedBox(height: 16),

                  // Timeline list
                  if (filteredEvents.isEmpty)
                    EmptyState(
                      Icons.history_toggle_off_rounded,
                      'No $_typeFilter events recorded',
                      'Activity, documents and communication notes for this client will appear here.',
                    ).enter(i++)
                  else
                    for (var idx = 0; idx < filteredEvents.length; idx++)
                      _TimelineRow(
                        item: filteredEvents[idx],
                        isFirst: idx == 0,
                        isLast: idx == filteredEvents.length - 1,
                      ).enter(i++),
                ],
              ],
            ),
    );
  }
}

class _TimelineItem {
  final DateTime date;
  final String category;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  _TimelineItem({
    required this.date,
    required this.category,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.onDelete,
  });
}

class _TimelineRow extends StatelessWidget {
  final _TimelineItem item;
  final bool isFirst;
  final bool isLast;

  const _TimelineRow({
    required this.item,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator line + dot
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: .15),
                    shape: BoxShape.circle,
                    border: Border.all(color: item.color, width: 2),
                  ),
                  child: Icon(item.icon, size: 16, color: item.color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: C.border,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: CardContainer(
                radius: 16,
                padding: const EdgeInsets.all(13),
                onTap: item.onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(fmtDate(item.date), style: mono(11, color: C.dim, weight: FontWeight.w600)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: C.chipLight, borderRadius: BorderRadius.circular(6)),
                          child: Text(item.category.toUpperCase(), style: mono(9.5, color: C.muted, weight: FontWeight.w700)),
                        ),
                        if (item.onDelete != null) ...[
                          const SizedBox(width: 4),
                          Pressable(
                            onTap: item.onDelete,
                            child: const Icon(Icons.delete_outline_rounded, size: 16, color: C.dim),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: C.text), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(item.subtitle, style: const TextStyle(fontSize: 12, color: C.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
