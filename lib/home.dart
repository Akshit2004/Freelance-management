import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'clients.dart';
import 'docs.dart';
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

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _searchController = TextEditingController();
  String _activeFilter = 'All'; // 'All', 'Clients', 'Invoices', 'Quotations', 'Projects'

  static const _filterOptions = ['All', 'Clients', 'Invoices', 'Quotations', 'Projects'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _activeFilter = 'All';
    });
  }

  bool _matchesClient(Client c, String q) {
    final tokens = q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (tokens.isEmpty) return true;
    final hay = [c.name, c.company, c.contact, c.email, c.phone, c.address, c.gstin, c.notes].join(' ').toLowerCase();
    return tokens.every(hay.contains);
  }

  bool _matchesDoc(Doc d, Store s, String q) {
    final tokens = q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (tokens.isEmpty) return true;
    final client = s.client(d.clientId);
    final hay = [
      d.number,
      d.title,
      client?.name ?? '',
      client?.company ?? '',
      d.notes,
      d.terms,
      d.shownStatus,
      d.status,
      d.isInvoice ? 'invoice' : 'quotation quote',
      money(d.total),
      d.total.toString(),
      for (final i in d.items) i.desc,
    ].join(' ').toLowerCase();
    return tokens.every(hay.contains);
  }

  bool _matchesProject(Project p, Store s, String q) {
    final tokens = q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (tokens.isEmpty) return true;
    final client = s.client(p.clientId);
    final hay = [
      p.name,
      client?.name ?? '',
      client?.company ?? '',
      p.status,
      p.notes,
      p.next,
      money(p.budget),
      p.budget.toString(),
      'project',
      for (final t in p.todos) t.text,
      for (final t in p.allLeaves) t.text,
    ].join(' ').toLowerCase();
    return tokens.every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final nav = context.read<NavController>();

    final query = _searchController.text.trim();
    final isSearching = query.isNotEmpty || _activeFilter != 'All';

    // Search and filter datasets
    final matchedClients = s.clients.where((c) => _matchesClient(c, query)).toList();
    final matchedInvoices = s.invoices.where((d) => _matchesDoc(d, s, query)).toList();
    final matchedQuotes = s.docs.where((d) => !d.isInvoice && _matchesDoc(d, s, query)).toList();
    final matchedProjects = s.projects.where((p) => _matchesProject(p, s, query)).toList();
    final totalMatches = matchedClients.length + matchedInvoices.length + matchedQuotes.length + matchedProjects.length;

    // Home dashboard metrics
    final activeProjects = s.projects.where((p) => p.status == 'active').toList();
    final pendingQuotes = s.docs.where((d) => !d.isInvoice && d.status == 'sent').length;
    final overdueDocs = s.docs.where((d) => d.overdue).toList();
    final overdueAmt = overdueDocs.fold(0.0, (a, d) => a + d.total);
    final outstanding = s.invoices.where((d) => d.status == 'sent' || d.status == 'overdue').fold(0.0, (a, d) => a + d.total);
    final collected = s.paid;
    final months = trailingMonths(s.docs);
    final hasChart = months.any((m) => m.value > 0);

    // Projects with a deadline
    final open = s.projects.where((p) => p.status != 'done').toList();
    final due = open.where((p) => p.deadline != null).toList()..sort((a, b) => a.deadline!.compareTo(b.deadline!));

    final now = DateTime.now();
    final dateStr = DateFormat('EEEE · MMM d').format(now).toUpperCase();
    final name = s.profile.bizName.trim().isNotEmpty ? s.profile.bizName.trim() : s.profile.ownerName.trim();
    final studioName = name.isEmpty ? 'Welcome' : name;

    final (String, Color)? health = overdueAmt > 0 ? ('OVERDUE', C.red) : (collected > 0 || outstanding > 0 ? ('ON TRACK', C.green) : null);

    void openSettings() => Navigator.push(context, zoom(const SettingsPage()));
    var i = 0;

    int countForFilter(String f) => switch (f) {
          'Clients' => matchedClients.length,
          'Invoices' => matchedInvoices.length,
          'Quotations' => matchedQuotes.length,
          'Projects' => matchedProjects.length,
          _ => totalMatches,
        };

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
        const SizedBox(height: 14),

        // ------------------ TOP SEARCH & FILTERS BAR ------------------
        Material(
          color: Colors.transparent,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontFamily: 'Grotesk', fontSize: 14.5, color: C.text),
            decoration: InputDecoration(
              hintText: 'Search clients, invoices, quotes, projects...',
              hintStyle: const TextStyle(color: C.dim, fontSize: 13.5),
              prefixIcon: Icon(Icons.search_rounded, color: query.isNotEmpty ? C.orange : C.muted, size: 21),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: C.muted),
                      onPressed: _clearSearch,
                      tooltip: 'Clear search',
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              filled: true,
              fillColor: C.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.dark, width: 1.5)),
            ),
          ),
        ).enter(i++),
        const SizedBox(height: 10),

        // Quick Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in _filterOptions)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Pressable(
                    onTap: () => setState(() => _activeFilter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                      decoration: BoxDecoration(
                        color: _activeFilter == f ? C.dark : C.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _activeFilter == f ? C.dark : C.border),
                      ),
                      child: Text(
                        '$f (${countForFilter(f)})',
                        style: TextStyle(
                          fontFamily: 'Grotesk',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _activeFilter == f ? C.textLight : C.muted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ).enter(i++),
        const SizedBox(height: 16),

        // ------------------ DYNAMIC CONTENT: SEARCH RESULTS OR DASHBOARD ------------------
        if (isSearching) ...[
          // Results Header
          Row(
            children: [
              Expanded(
                child: Text(
                  _activeFilter == 'All'
                      ? 'FOUND $totalMatches ${totalMatches == 1 ? 'MATCH' : 'MATCHES'}'
                      : '${_activeFilter.toUpperCase()} · ${countForFilter(_activeFilter)}',
                  style: mono(11, color: C.dim, letterSpacing: 0.9, weight: FontWeight.w700),
                ),
              ),
              Pressable(
                onTap: _clearSearch,
                child: const Text('Back to Dashboard', style: TextStyle(fontFamily: 'Grotesk', fontSize: 12.5, fontWeight: FontWeight.w700, color: C.orange)),
              ),
            ],
          ).enter(i++),
          const SizedBox(height: 12),

          if (totalMatches == 0)
            Column(
              children: [
                EmptyState(
                  Icons.search_off_rounded,
                  'No matches found',
                  query.isNotEmpty ? 'No item matches "$query" in $_activeFilter.' : 'No records exist in $_activeFilter.',
                ),
                const SizedBox(height: 6),
                Pressable(
                  onTap: _clearSearch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(14)),
                    child: const Text('Clear search & filters',
                        style: TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 13.5, color: C.textLight)),
                  ),
                ),
              ],
            ).enter(i++)
          else ...[
            // 1. Clients section
            if ((_activeFilter == 'All' || _activeFilter == 'Clients') && matchedClients.isNotEmpty) ...[
              if (_activeFilter == 'All')
                _SectionTitle('CLIENTS', matchedClients.length).enter(i++),
              for (final c in matchedClients)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SearchResultClientCard(client: c, store: s).enter(i++),
                ),
            ],

            // 2. Invoices section
            if ((_activeFilter == 'All' || _activeFilter == 'Invoices') && matchedInvoices.isNotEmpty) ...[
              if (_activeFilter == 'All')
                _SectionTitle('INVOICES', matchedInvoices.length).enter(i++),
              for (final d in matchedInvoices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SearchResultDocCard(doc: d, store: s).enter(i++),
                ),
            ],

            // 3. Quotations section
            if ((_activeFilter == 'All' || _activeFilter == 'Quotations') && matchedQuotes.isNotEmpty) ...[
              if (_activeFilter == 'All')
                _SectionTitle('QUOTATIONS', matchedQuotes.length).enter(i++),
              for (final d in matchedQuotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SearchResultDocCard(doc: d, store: s).enter(i++),
                ),
            ],

            // 4. Projects section
            if ((_activeFilter == 'All' || _activeFilter == 'Projects') && matchedProjects.isNotEmpty) ...[
              if (_activeFilter == 'All')
                _SectionTitle('PROJECTS', matchedProjects.length).enter(i++),
              for (final p in matchedProjects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SearchResultProjectCard(project: p, store: s).enter(i++),
                ),
            ],
          ],
        ] else ...[
          // NORMAL DASHBOARD VIEW

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
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;
  const _SectionTitle(this.title, this.count);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Text('$title · $count', style: mono(11, color: C.dim, weight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: C.border, thickness: 1)),
        ],
      ),
    );
  }
}

class _SearchResultClientCard extends StatelessWidget {
  final Client client;
  final Store store;
  const _SearchResultClientCard({required this.client, required this.store});

  @override
  Widget build(BuildContext context) {
    final ledger = ClientLedger.of(store, client.id);
    final active = store.projects.where((p) => p.clientId == client.id && p.status == 'active').length;
    final sub = client.company.isNotEmpty
        ? client.company
        : (client.contact.isNotEmpty ? client.contact : (client.email.isNotEmpty ? client.email : 'Client'));

    return CardContainer(
      radius: 18,
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.push(context, zoom(ClientDetailPage(client.id))),
      child: Row(
        children: [
          AvatarSquircle(client.name, color: Color(client.colorValue), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(client.name, style: display(15.5, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: C.blueLight, borderRadius: BorderRadius.circular(6)),
                      child: Text('CLIENT', style: mono(9.5, color: C.blueText, weight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 12, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('$active active project${active == 1 ? '' : 's'}', style: mono(11, color: C.dim)),
              ],
            ),
          ),
          if (ledger.outstanding > 0) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money(ledger.outstanding), style: mono(13, color: C.red, weight: FontWeight.w700)),
                Text('unpaid', style: mono(10, color: C.muted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchResultDocCard extends StatelessWidget {
  final Doc doc;
  final Store store;
  const _SearchResultDocCard({required this.doc, required this.store});

  @override
  Widget build(BuildContext context) {
    final clientName = store.clientName(doc.clientId);
    final isInv = doc.isInvoice;
    final title = doc.title.isNotEmpty ? doc.title : (isInv ? 'Invoice' : 'Quotation');

    return CardContainer(
      radius: 18,
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.push(context, zoom(DocDetailPage(doc.id))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isInv ? (doc.overdue ? C.redLight : C.blueLight) : C.amberLight.withValues(alpha: .3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isInv ? Icons.receipt_long_rounded : Icons.request_quote_rounded,
              size: 20,
              color: isInv ? (doc.overdue ? C.red : C.blue) : C.amber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${doc.number} · ${fmtDate(doc.date)}', style: mono(11, color: C.dim)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isInv ? C.blueLight : C.chipBg,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(isInv ? 'INVOICE' : 'QUOTE', style: mono(9, color: isInv ? C.blueText : C.dim, weight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: C.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(clientName, style: const TextStyle(fontSize: 12, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money(doc.total), style: mono(14, weight: FontWeight.w700, color: C.text)),
              const SizedBox(height: 4),
              StatusPill(doc.shownStatus),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchResultProjectCard extends StatelessWidget {
  final Project project;
  final Store store;
  const _SearchResultProjectCard({required this.project, required this.store});

  @override
  Widget build(BuildContext context) {
    final clientName = store.clientName(project.clientId);
    final days = project.deadline != null ? daysUntil(project.deadline!) : null;

    return CardContainer(
      radius: 18,
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.push(context, zoom(ProjectDetailPage(project.id))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: C.greenLight, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.folder_rounded, size: 20, color: C.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        project.name.isEmpty ? 'Untitled project' : project.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: C.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(color: C.greenLight, borderRadius: BorderRadius.circular(5)),
                      child: Text('PROJECT', style: mono(9, color: C.greenText, weight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('$clientName · ${project.doneTasksCount}/${project.totalTasksCount} tasks done',
                    style: const TextStyle(fontSize: 12, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (project.deadline != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    dueLabel(project.deadline!),
                    style: mono(10.5, color: (days != null && days <= 2) ? C.red : C.muted, weight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (project.budget > 0)
                Text(money(project.budget), style: mono(13, weight: FontWeight.w700, color: C.text)),
              const SizedBox(height: 4),
              StatusPill(project.status),
            ],
          ),
        ],
      ),
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
        padding: EdgeInsets.all(20),
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
    return CardContainer(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      radius: 18,
      child: Column(
        children: [
          for (final (k, a) in items.indexed)
            _ActivityLine(
              title: a.text,
              when: ago(a.at),
              color: tone(a.tone),
              isLast: k == items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _ActivityLine extends StatelessWidget {
  final String title, when;
  final Color color;
  final bool isLast;
  const _ActivityLine({required this.title, required this.when, required this.color, required this.isLast});

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
