import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'ai_svg_animator.dart';
import 'client_timeline.dart';
import 'follow_ups.dart';
import 'magic.dart';
import 'models.dart';
import 'payment_tracking.dart';
import 'services_catalogue.dart';
import 'settings.dart';
import 'ui.dart';

/// Opens the redesigned Workspace Tools Command Center sheet.
void openBottomSubMenu(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => const _SubMenuSheet(),
  );
}

class _SubMenuSheet extends StatelessWidget {
  const _SubMenuSheet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final pendingFollowUps = s.docs.where((d) => (!d.isInvoice && d.status == 'sent') || (d.isInvoice && (d.status == 'sent' || d.overdue))).length;
    final overdueCount = s.docs.where((d) => d.overdue).length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final items = [
      (
        title: 'Service Catalogue',
        desc: 'Reusable service packages, standard rates & line items',
        icon: Icons.inventory_2_rounded,
        color: C.orange,
        badge: '${s.services.length} items',
        badgeColor: const Color(0xFFFFEBE0),
        badgeTextColor: C.orangeDark,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const ServiceCataloguePage()));
        },
      ),
      (
        title: 'Follow-up Reminders',
        desc: 'Chase unpaid invoices & quotations with WhatsApp/Email',
        icon: Icons.notifications_active_rounded,
        color: C.amber,
        badge: pendingFollowUps > 0 ? '$pendingFollowUps pending' : 'Up to date',
        badgeColor: pendingFollowUps > 0 ? C.amberLight.withValues(alpha: .5) : C.chipBg,
        badgeTextColor: pendingFollowUps > 0 ? const Color(0xFFB45309) : C.muted,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const FollowUpsPage()));
        },
      ),
      (
        title: 'Client Timeline',
        desc: 'Chronological history of work, documents, payments & notes',
        icon: Icons.timeline_rounded,
        color: C.blue,
        badge: null,
        badgeColor: Colors.transparent,
        badgeTextColor: Colors.transparent,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const ClientTimelinePage()));
        },
      ),
      (
        title: 'Payment Tracking',
        desc: 'Full, partial, unpaid & overdue invoices with payment methods',
        icon: Icons.payments_rounded,
        color: C.green,
        badge: overdueCount > 0 ? '$overdueCount overdue' : null,
        badgeColor: C.redLight,
        badgeTextColor: C.redText,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const PaymentTrackingPage()));
        },
      ),
      (
        title: 'Magic AI Scratchpad',
        desc: 'On-device Gemma 2B converts rough notes to quotes & invoices',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF9C27B0),
        badge: 'Gemma 2B',
        badgeColor: const Color(0xFFF3E5F5),
        badgeTextColor: const Color(0xFF6A1B9A),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const MagicPage()));
        },
      ),
      (
        title: 'Settings & Cloud Backup',
        desc: 'Encrypted MongoDB sync, profile, hourly rate & taxes',
        icon: Icons.cloud_sync_rounded,
        color: C.dark,
        badge: null,
        badgeColor: Colors.transparent,
        badgeTextColor: Colors.transparent,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, zoom(const SettingsPage()));
        },
      ),
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 6, 20, bottomInset + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero Command Deck Header with Animated AI SVG
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF261E1A),
                      Color(0xFF1B1614),
                      Color(0xFF12100E),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: C.orange.withValues(alpha: 0.28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .18),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(
                        child: AiSvgAnimator(
                          size: 50,
                          showGlow: true,
                          primaryColor: Color(0xFFFF5722),
                          secondaryColor: Color(0xFFFFB300),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'WORKSPACE COMMAND DECK',
                                style: mono(10, color: const Color(0xFFFFAB91), weight: FontWeight.w700, letterSpacing: 1.1),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Freelance Intelligence Tools',
                            style: TextStyle(
                              fontFamily: 'Grotesk',
                              fontWeight: FontWeight.w700,
                              fontSize: 16.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${s.services.length} services · ${s.clients.length} clients · ${s.projects.length} projects',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFBCAAA4)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Tool Cards
              for (final (idx, it) in items.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Pressable(
                    onTap: it.onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12.5),
                      decoration: BoxDecoration(
                        color: C.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: C.borderLight),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .025),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  it.color.withValues(alpha: .18),
                                  it.color.withValues(alpha: .08),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: it.color.withValues(alpha: .22)),
                            ),
                            child: Icon(it.icon, color: it.color, size: 22),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        it.title,
                                        style: const TextStyle(
                                          fontFamily: 'Grotesk',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                          color: C.text,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (it.badge != null) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: it.badgeColor,
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          it.badge!,
                                          style: mono(9.5, color: it.badgeTextColor, weight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2.5),
                                Text(
                                  it.desc,
                                  style: const TextStyle(fontSize: 11.8, color: C.muted, height: 1.3),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: C.dim),
                        ],
                      ),
                    ),
                  ),
                ).animate().fadeIn(duration: 220.ms, delay: (idx * 30).ms).slideY(begin: 0.1, duration: 240.ms, curve: Curves.easeOutQuad),
            ],
          ),
        ),
      ),
    );
  }
}
