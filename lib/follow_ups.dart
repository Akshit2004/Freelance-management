import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'docs.dart';
import 'models.dart';
import 'motion.dart';
import 'ui.dart';

class FollowUpsPage extends StatefulWidget {
  const FollowUpsPage({super.key});

  @override
  State<FollowUpsPage> createState() => _FollowUpsPageState();
}

class _FollowUpsPageState extends State<FollowUpsPage> {
  String _filter = 'All'; // 'All', 'Quotes', 'Unpaid', 'Overdue'

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();

    final pendingQuotes = s.docs.where((d) => !d.isInvoice && d.status == 'sent').toList();
    final unpaidInvoices = s.invoices.where((d) => d.status == 'sent' || d.status == 'overdue').toList();
    final overdueInvoices = unpaidInvoices.where((d) => d.overdue).toList();

    final allItems = <Doc>[
      if (_filter == 'All' || _filter == 'Quotes') ...pendingQuotes,
      if (_filter == 'All' || _filter == 'Unpaid' || _filter == 'Overdue')
        ...(_filter == 'Overdue' ? overdueInvoices : unpaidInvoices),
    ]..sort((a, b) {
        // Overdue first, then nearest due date or oldest sent
        if (a.overdue && !b.overdue) return -1;
        if (!a.overdue && b.overdue) return 1;
        return a.due.compareTo(b.due);
      });

    final totalOutstanding = unpaidInvoices.fold(0.0, (sum, d) => sum + d.balanceDue);
    final totalQuotes = pendingQuotes.fold(0.0, (sum, d) => sum + d.total);

    var i = 0;

    return Screen(
      title: 'Follow-up Reminders',
      body: RefreshListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          // Summary Banner
          CardContainer(
            color: C.dark,
            borderColor: C.dark,
            radius: 22,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PENDING FOLLOW-UPS', style: mono(10.5, color: C.dimLight, letterSpacing: 1.0)),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${pendingQuotes.length + unpaidInvoices.length}', style: display(32, color: C.textLight)),
                    const SizedBox(width: 8),
                    Text('items needing attention', style: const TextStyle(fontSize: 13, color: C.dimLight)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Unpaid Invoices', style: mono(11, color: C.dimLight)),
                          const SizedBox(height: 2),
                          Text(money(totalOutstanding), style: mono(14, color: C.textLight, weight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quotes Pending', style: mono(11, color: C.dimLight)),
                          const SizedBox(height: 2),
                          Text(money(totalQuotes), style: mono(14, color: C.textLight, weight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ).enter(i++),
          const SizedBox(height: 14),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in [
                  ('All', pendingQuotes.length + unpaidInvoices.length),
                  ('Quotes', pendingQuotes.length),
                  ('Unpaid', unpaidInvoices.length),
                  ('Overdue', overdueInvoices.length),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Pressable(
                      onTap: () => setState(() => _filter = f.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _filter == f.$1 ? C.dark : C.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _filter == f.$1 ? C.dark : C.border),
                        ),
                        child: Row(
                          children: [
                            Text(
                              f.$1,
                              style: TextStyle(
                                fontFamily: 'Grotesk',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _filter == f.$1 ? C.textLight : C.muted,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _filter == f.$1 ? Colors.white.withValues(alpha: .2) : C.chipBg,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '${f.$2}',
                                style: mono(10.5, color: _filter == f.$1 ? C.textLight : C.muted, weight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ).enter(i++),
          const SizedBox(height: 16),

          // Items List
          if (allItems.isEmpty)
            EmptyState(
              Icons.done_all_rounded,
              'All caught up!',
              'No pending quotes or unpaid invoices need follow-up right now.',
            ).enter(i++)
          else
            for (final doc in allItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FollowUpCard(doc: doc, store: s).enter(i++),
              ),
        ],
      ),
    );
  }
}

class _FollowUpCard extends StatelessWidget {
  final Doc doc;
  final Store store;

  const _FollowUpCard({required this.doc, required this.store});

  void _openFollowUpModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _FollowUpActionSheet(doc: doc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = store.client(doc.clientId);
    final clientName = client?.name ?? 'Unknown client';
    final followUps = store.followUpsFor(doc.id);
    final lastFollowUp = followUps.firstOrNull;

    final now = DateTime.now();
    final daysSinceDate = now.difference(doc.date).inDays;
    final overdue = doc.overdue;
    final daysLate = overdue ? daysOverdue(doc) : 0;

    final statusText = overdue
        ? 'Overdue by $daysLate ${daysLate == 1 ? 'day' : 'days'}'
        : (doc.isInvoice ? 'Due ${fmtDate(doc.due)}' : 'Sent $daysSinceDate ${daysSinceDate == 1 ? 'day' : 'days'} ago');

    return CardContainer(
      radius: 20,
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.push(context, zoom(DocDetailPage(doc.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: overdue ? C.redLight : (doc.isInvoice ? C.blueLight : C.amberLight.withValues(alpha: .3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  doc.isInvoice ? Icons.receipt_long_rounded : Icons.request_quote_rounded,
                  size: 20,
                  color: overdue ? C.red : (doc.isInvoice ? C.blue : C.amber),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(doc.number, style: mono(12, color: C.dim, weight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: doc.isInvoice ? C.blueLight : C.chipBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(doc.isInvoice ? 'INVOICE' : 'QUOTE', style: mono(9.5, color: doc.isInvoice ? C.blueText : C.dim, weight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(clientName, style: display(16, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (doc.title.trim().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(doc.title.trim(), style: const TextStyle(fontSize: 12.5, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(money(doc.balanceDue > 0 ? doc.balanceDue : doc.total), style: mono(15, weight: FontWeight.w700, color: overdue ? C.red : C.text)),
                  const SizedBox(height: 2),
                  Text(statusText, style: mono(10.5, color: overdue ? C.redText : C.muted, weight: overdue ? FontWeight.w700 : FontWeight.w500)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Last follow-up notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: C.chipLight, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(
                  lastFollowUp != null ? Icons.mark_email_read_rounded : Icons.schedule_rounded,
                  size: 15,
                  color: lastFollowUp != null ? C.green : C.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    lastFollowUp != null
                        ? 'Last follow-up: ${fmtDate(lastFollowUp.date)} via ${lastFollowUp.channel}${lastFollowUp.notes.isNotEmpty ? ' ("${lastFollowUp.notes}")' : ''}'
                        : 'No follow-up recorded yet.',
                    style: const TextStyle(fontSize: 11.5, color: C.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: Pressable(
                  onTap: () => _openFollowUpModal(context),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.send_rounded, size: 15, color: C.textLight),
                        SizedBox(width: 6),
                        Text('Follow Up Now', style: TextStyle(fontFamily: 'Grotesk', fontSize: 13, fontWeight: FontWeight.w700, color: C.textLight)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Pressable(
                onTap: () => Navigator.push(context, zoom(DocDetailPage(doc.id))),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.border),
                  ),
                  alignment: Alignment.center,
                  child: const Text('View Doc', style: TextStyle(fontFamily: 'Grotesk', fontSize: 13, fontWeight: FontWeight.w600, color: C.text)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FollowUpActionSheet extends StatefulWidget {
  final Doc doc;
  const _FollowUpActionSheet({required this.doc});

  @override
  State<_FollowUpActionSheet> createState() => _FollowUpActionSheetState();
}

class _FollowUpActionSheetState extends State<_FollowUpActionSheet> {
  String _channel = 'WhatsApp';
  late final TextEditingController _message;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final d = widget.doc;
    final clientName = store.clientName(d.clientId);
    final biz = store.profile.bizName.isNotEmpty ? store.profile.bizName : store.profile.ownerName;

    if (d.isInvoice) {
      if (d.overdue) {
        _message = TextEditingController(
          text: 'Hi $clientName,\n\nHope you are doing well. Just following up regarding invoice ${d.number} for ${money(d.balanceDue)}, which was due on ${fmtDate(d.due)}. Please let us know once the payment is scheduled.\n\nThank you,\n$biz',
        );
      } else {
        _message = TextEditingController(
          text: 'Hi $clientName,\n\nHope you are having a great week! A friendly reminder regarding invoice ${d.number} for ${money(d.balanceDue)}, due on ${fmtDate(d.due)}. Please let us know if you need any additional details.\n\nBest regards,\n$biz',
        );
      }
    } else {
      _message = TextEditingController(
        text: 'Hi $clientName,\n\nFollowing up on our quotation ${d.number} for ${money(d.total)} sent recently. We would love to know if you had any questions or if you are ready to get started!\n\nBest regards,\n$biz',
      );
    }
  }

  @override
  void dispose() {
    _message.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _shareOrCopy(bool share) {
    if (share) {
      SharePlus.instance.share(ShareParams(
        text: _message.text.trim(),
        subject: 'Follow-up on ${widget.doc.number}',
      ));
    } else {
      Clipboard.setData(ClipboardData(text: _message.text.trim()));
      toast(context, 'Message copied to clipboard');
    }

    // Auto-record follow-up
    context.read<Store>().addFollowUp(FollowUpRecord(
          docId: widget.doc.id,
          clientId: widget.doc.clientId,
          channel: _channel,
          notes: _notes.text.trim().isNotEmpty ? _notes.text.trim() : 'Follow-up message sent',
        ));
    Navigator.pop(context);
    toast(context, 'Follow-up logged successfully');
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, inset + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text('Follow Up on ${widget.doc.number}', style: display(19))),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),
            // Channel selection
            Row(
              children: [
                for (final ch in ['WhatsApp', 'Email', 'Call', 'Message'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Pressable(
                      onTap: () => setState(() => _channel = ch),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _channel == ch ? C.dark : C.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _channel == ch ? C.dark : C.border),
                        ),
                        child: Text(
                          ch,
                          style: TextStyle(
                            fontFamily: 'Grotesk',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _channel == ch ? C.textLight : C.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Message input
            TextField(
              controller: _message,
              maxLines: 5,
              style: const TextStyle(fontSize: 13.5, height: 1.4),
              decoration: InputDecoration(
                labelText: 'Follow-up Message Template',
                filled: true,
                fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: InputDecoration(
                labelText: 'Optional note for your records',
                hintText: 'e.g. Client mentioned waiting for approvals',
                filled: true,
                fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: () => _shareOrCopy(false),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: C.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: C.border),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.copy_rounded, size: 16, color: C.text),
                          SizedBox(width: 6),
                          Text('Copy & Log', style: TextStyle(fontFamily: 'Grotesk', fontSize: 13.5, fontWeight: FontWeight.w700, color: C.text)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Pressable(
                    onTap: () => _shareOrCopy(true),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.share_rounded, size: 16, color: C.textLight),
                          SizedBox(width: 6),
                          Text('Share & Log', style: TextStyle(fontFamily: 'Grotesk', fontSize: 13.5, fontWeight: FontWeight.w700, color: C.textLight)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
