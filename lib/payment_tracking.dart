import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'docs.dart';
import 'models.dart';
import 'motion.dart';
import 'ui.dart';

class PaymentTrackingPage extends StatefulWidget {
  const PaymentTrackingPage({super.key});

  @override
  State<PaymentTrackingPage> createState() => _PaymentTrackingPageState();
}

class _PaymentTrackingPageState extends State<PaymentTrackingPage> {
  String _activeTab = 'All'; // 'All', 'Unpaid', 'Partially Paid', 'Paid', 'Overdue'

  void _openRecordPaymentDialog(BuildContext context, Doc doc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RecordPaymentSheet(doc: doc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final invoices = s.invoices.toList()
      ..sort((a, b) {
        if (a.overdue && !b.overdue) return -1;
        if (!a.overdue && b.overdue) return 1;
        return b.date.compareTo(a.date);
      });

    final paidInvoices = invoices.where((d) => d.status == 'paid' || d.paidAmount >= d.total).toList();
    final partialInvoices = invoices.where((d) => d.isPartiallyPaid).toList();
    final overdueInvoices = invoices.where((d) => d.overdue && d.paidAmount < d.total).toList();
    final unpaidInvoices = invoices.where((d) => d.status == 'sent' && d.paidAmount == 0 && !d.overdue).toList();

    final shownInvoices = switch (_activeTab) {
      'Paid' => paidInvoices,
      'Partially Paid' => partialInvoices,
      'Overdue' => overdueInvoices,
      'Unpaid' => unpaidInvoices,
      _ => invoices.where((d) => d.status != 'draft').toList(),
    };

    final totalInvoiced = invoices.where((d) => d.status != 'draft').fold(0.0, (sum, d) => sum + d.total);
    final totalCollected = s.paid;
    final totalOutstanding = s.outstanding;

    var i = 0;

    return Screen(
      title: 'Payment Tracking',
      body: RefreshListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          // Cash flow metric header
          CardContainer(
            color: C.dark,
            borderColor: C.dark,
            radius: 22,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PAYMENT STATUS OVERVIEW', style: mono(10.5, color: C.dimLight, letterSpacing: 1.0)),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(money(totalCollected), style: display(32, color: C.textLight)),
                    const SizedBox(width: 8),
                    Text('collected', style: const TextStyle(fontSize: 13, color: C.dimLight)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Outstanding', style: mono(11, color: C.dimLight)),
                          const SizedBox(height: 2),
                          Text(money(totalOutstanding), style: mono(14, color: C.redLight, weight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Invoiced', style: mono(11, color: C.dimLight)),
                          const SizedBox(height: 2),
                          Text(money(totalInvoiced), style: mono(14, color: C.textLight, weight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ).enter(i++),
          const SizedBox(height: 14),

          // Tab Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tab in [
                  ('All', invoices.where((d) => d.status != 'draft').length),
                  ('Unpaid', unpaidInvoices.length),
                  ('Partially Paid', partialInvoices.length),
                  ('Overdue', overdueInvoices.length),
                  ('Paid', paidInvoices.length),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Pressable(
                      onTap: () => setState(() => _activeTab = tab.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                        decoration: BoxDecoration(
                          color: _activeTab == tab.$1 ? C.dark : C.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _activeTab == tab.$1 ? C.dark : C.border),
                        ),
                        child: Row(
                          children: [
                            Text(
                              tab.$1,
                              style: TextStyle(
                                fontFamily: 'Grotesk',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _activeTab == tab.$1 ? C.textLight : C.muted,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _activeTab == tab.$1 ? Colors.white.withValues(alpha: .2) : C.chipBg,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '${tab.$2}',
                                style: mono(10, color: _activeTab == tab.$1 ? C.textLight : C.muted, weight: FontWeight.w700),
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

          // Invoices List
          if (shownInvoices.isEmpty)
            EmptyState(
              Icons.receipt_long_rounded,
              'No $_activeTab invoices',
              'Invoices matching this payment status will appear here.',
            ).enter(i++)
          else
            for (final doc in shownInvoices)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PaymentInvoiceCard(
                  doc: doc,
                  store: s,
                  onRecordPayment: () => _openRecordPaymentDialog(context, doc),
                ).enter(i++),
              ),
        ],
      ),
    );
  }
}

class _PaymentInvoiceCard extends StatelessWidget {
  final Doc doc;
  final Store store;
  final VoidCallback onRecordPayment;

  const _PaymentInvoiceCard({
    required this.doc,
    required this.store,
    required this.onRecordPayment,
  });

  @override
  Widget build(BuildContext context) {
    final clientName = store.clientName(doc.clientId);
    final total = doc.total;
    final paid = doc.paidAmount;
    final balance = doc.balanceDue;
    final progress = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
    final isFullyPaid = paid >= total || doc.status == 'paid';

    final paymentStatusLabel = doc.overdue
        ? 'Overdue'
        : (isFullyPaid
            ? 'Paid'
            : (doc.isPartiallyPaid ? 'Partially Paid' : 'Unpaid'));

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${doc.number} · ${fmtDate(doc.date)}', style: mono(11.5, color: C.dim, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(clientName, style: display(16, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (doc.title.trim().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(doc.title.trim(), style: const TextStyle(fontSize: 12.5, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(money(total), style: mono(16, weight: FontWeight.w700, color: C.text)),
                  const SizedBox(height: 3),
                  StatusPill(paymentStatusLabel),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Payment Progress Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Paid: ${money(paid)} (${(progress * 100).round()}%)', style: mono(11, color: C.green, weight: FontWeight.w600)),
                  Text(balance > 0 ? 'Due: ${money(balance)}' : 'Fully Settled',
                      style: mono(11, color: balance > 0 ? (doc.overdue ? C.red : C.muted) : C.green, weight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: C.chipBg,
                  valueColor: AlwaysStoppedAnimation(isFullyPaid ? C.green : (doc.isPartiallyPaid ? C.amber : C.dim)),
                ),
              ),
            ],
          ),

          // Payment Transactions List
          if (doc.payments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: C.chipLight, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TRANSACTIONS (${doc.payments.length})', style: mono(10, color: C.dim, weight: FontWeight.w700, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  for (final p in doc.payments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 14, color: C.green),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${fmtDate(p.date)} · ${p.method}${p.reference.isNotEmpty ? ' (${p.reference})' : ''}',
                              style: const TextStyle(fontSize: 12, color: C.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(money(p.amount), style: mono(12, color: C.text, weight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!isFullyPaid)
                Pressable(
                  onTap: onRecordPayment,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_card_rounded, size: 15, color: C.textLight),
                        SizedBox(width: 6),
                        Text('Record Payment', style: TextStyle(fontFamily: 'Grotesk', fontSize: 13, fontWeight: FontWeight.w700, color: C.textLight)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Pressable(
                onTap: () => Navigator.push(context, zoom(DocDetailPage(doc.id))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.border),
                  ),
                  child: const Text('View Invoice', style: TextStyle(fontFamily: 'Grotesk', fontSize: 13, fontWeight: FontWeight.w600, color: C.text)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordPaymentSheet extends StatefulWidget {
  final Doc doc;
  const _RecordPaymentSheet({required this.doc});

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  late final TextEditingController _amount;
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  String _method = 'Bank Transfer';

  static const methods = ['Bank Transfer', 'UPI', 'Credit Card', 'Cash', 'Cheque', 'PayPal', 'Stripe', 'Other'];

  @override
  void initState() {
    super.initState();
    final remaining = widget.doc.balanceDue;
    _amount = TextEditingController(text: remaining > 0 ? (remaining % 1 == 0 ? remaining.toInt().toString() : remaining.toString()) : '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final amt = double.tryParse(_amount.text.trim()) ?? 0;
    if (amt <= 0) {
      toast(context, 'Please enter a valid payment amount');
      return;
    }

    final record = PaymentRecord(
      amount: amt,
      date: _date,
      method: _method,
      reference: _ref.text.trim(),
      notes: _notes.text.trim(),
    );

    context.read<Store>().recordPayment(widget.doc.id, record);
    Navigator.pop(context);
    toast(context, 'Payment of ${money(amt)} recorded on ${widget.doc.number}');
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Record Payment', style: display(20)),
                      Text('${widget.doc.number} · Balance Due: ${money(widget.doc.balanceDue)}', style: mono(12, color: C.muted)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Amount Received (${store.profile.currency})',
                filled: true,
                fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: C.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: C.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16, color: C.muted),
                          const SizedBox(width: 8),
                          Text(fmtDate(_date), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: InputDecoration(
                      labelText: 'Method',
                      filled: true,
                      fillColor: C.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
                    ),
                    items: [
                      for (final m in methods)
                        DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (v) => v != null ? setState(() => _method = v) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ref,
              decoration: InputDecoration(
                labelText: 'Reference / UTR / Transaction ID (Optional)',
                hintText: 'e.g. UTR-987654321, UPI Ref, Cheque #',
                filled: true,
                fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: InputDecoration(
                labelText: 'Payment Notes (Optional)',
                hintText: 'e.g. Received via NEFT from HDFC Bank',
                filled: true,
                fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              ),
            ),
            const SizedBox(height: 20),
            Pressable(
              onTap: _submit,
              child: Container(
                height: 50,
                decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.center,
                child: const Text('Confirm Payment',
                    style: TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 15, color: C.textLight)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
