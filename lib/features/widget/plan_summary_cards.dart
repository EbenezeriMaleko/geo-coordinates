import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../workspaces/workspace_provider.dart';
import '../subscriptions/plans_access_page.dart';
import '../subscriptions/subscription_provider.dart';

/// Shows the active plan of the current workspace (personal or company)
/// on the Profile page. Tapping opens Plans & Access.
/// Colors follow Theme.of(context).colorScheme.primary, so place it
/// inside the Profile page's accent Theme.
class PlanSummaryCard extends ConsumerWidget {
  const PlanSummaryCard({super.key});

  static const Color _amber = Color(0xFFB26A00);
  static const Color _amberSoft = Color(0xFFFFF4E0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(subscriptionOverviewProvider);
    final workspace = ref.watch(workspaceProvider);
    final accent = Theme.of(context).colorScheme.primary;

    void open() => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PlansAccessPage()),
    );

    Widget shell({
      required String name,
      required String subtitle,
      bool pending = false,
      bool filled = false,
    }) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: open,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: filled
                      ? accent.withValues(alpha: 0.35)
                      : const Color(0xFFE8ECF0),
                  width: filled ? 1.3 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCrown,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CURRENT PLAN',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                            color: Colors.black45,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pending)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _amberSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Pending',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _amber,
                        ),
                      ),
                    )
                  else
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: Colors.black26,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return overview.when(
      loading: () => shell(
        name: 'Loading plan…',
        subtitle: workspace.label,
      ),
      // Even on error the card stays tappable so Plans & Access is reachable.
      error: (_, _) => shell(
        name: 'Plans & Access',
        subtitle: 'Tap to view plan details',
      ),
      data: (data) {
        final usage = data['usage'] is Map
            ? Map<String, dynamic>.from(data['usage'] as Map)
            : <String, dynamic>{};
        final subscription = data['subscription'] is Map
            ? data['subscription'] as Map
            : null;
        final plan = subscription?['plan'] is Map
            ? subscription!['plan'] as Map
            : null;
        final name =
            usage['plan_name']?.toString() ??
            plan?['name']?.toString() ??
            'No active plan';
        final ends = DateTime.tryParse(
          subscription?['ends_at']?.toString() ?? '',
        )?.toLocal();

        final String subtitle;
        if (subscription == null) {
          subtitle = '${workspace.label} · Tap to view available plans';
        } else if (ends != null) {
          subtitle =
              '${workspace.label} · Valid until ${MaterialLocalizations.of(context).formatMediumDate(ends)}';
        } else {
          subtitle = workspace.label;
        }

        return shell(
          name: name,
          subtitle: subtitle,
          pending: data['has_pending_request'] == true,
          filled: subscription != null,
        );
      },
    );
  }
}