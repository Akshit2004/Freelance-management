import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'client_timeline.dart';
import 'follow_ups.dart';
import 'models.dart';
import 'payment_tracking.dart';
import 'services_catalogue.dart';
import 'settings.dart';
import 'ui.dart';

void openBottomSubMenu(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.card,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => const _SubMenuSheet(),
  );
}

class _SubMenuSheet extends StatelessWidget {
  const _SubMenuSheet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final pendingFollowUps = s.docs.where((d) => (!d.isInvoice && d.status == 'sent') || (d.isInvoice && (d.status == 'sent' || d.overdue))).length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final items = [
      (
        title: 'Service Catalogue',
        desc: 'Reusable services, rates and packages',
        icon: Icons.inventory_2_rounded,
        color: C.orange,
        badge: '${s.services.length}',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const ServiceCataloguePage()));
        },
      ),
      (
        title: 'Follow-up Reminders',
        desc: 'Follow up on quotations & unpaid invoices',
        icon: Icons.notifications_active_rounded,
        color: C.amber,
        badge: pendingFollowUps > 0 ? '$pendingFollowUps' : null,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const FollowUpsPage()));
        },
      ),
      (
        title: 'Client Timeline',
        desc: 'Past work, documents, payments & notes',
        icon: Icons.timeline_rounded,
        color: C.blue,
        badge: null,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const ClientTimelinePage()));
        },
      ),
      (
        title: 'Payment Tracking',
        desc: 'Paid, partial, unpaid & overdue payments',
        icon: Icons.payments_rounded,
        color: C.green,
        badge: null,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const PaymentTrackingPage()));
        },
      ),
      (
        title: 'Settings & Cloud Backup',
        desc: 'Profile, MongoDB sync, AI model & taxes',
        icon: Icons.settings_rounded,
        color: C.dark,
        badge: null,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const SettingsPage()));
        },
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('More Workspace Tools', style: display(21)),
                          const SizedBox(height: 2),
                          const Text('Quick access to catalogue, reminders, timelines and tracking.',
                              style: TextStyle(fontSize: 12.5, color: C.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Pressable(
                    onTap: it.onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: C.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: C.borderLight),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: it.color.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(it.icon, color: it.color, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it.title, style: const TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 14.5, color: C.text)),
                                const SizedBox(height: 2),
                                Text(it.desc, style: const TextStyle(fontSize: 12, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          if (it.badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: it.color == C.amber ? C.amberLight.withValues(alpha: .4) : C.chipBg,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(it.badge!, style: mono(11, color: C.text, weight: FontWeight.w700)),
                            ),
                          ],
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: C.dim),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
