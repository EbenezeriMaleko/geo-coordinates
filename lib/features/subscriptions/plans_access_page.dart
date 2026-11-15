import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../widget/app_backarrow.dart'; // adjust to your file name/path
import '../widget/profile_widget.dart';
import '../workspaces/workspace_page_style.dart';
import '../workspaces/workspace_provider.dart';
import 'entitlement_provider.dart';
import 'feature_access_section.dart';
import 'subscription_provider.dart';
import 'plans_catalog.dart';

// ── Shared look for this page ──────────────────────────────────────
const Color _personalAccent = Color(0xFF001F3F);
const Color _companyAccent = Color(0xFF197568);
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _amber = Color(0xFFB26A00);
const Color _amberSoft = Color(0xFFFFF4E0);
const Color _green = Color(0xFF1B7F4B);
const Color _greenSoft = Color(0xFFE6F5EC);

String _date(dynamic value) {
  final date = DateTime.tryParse(value.toString())?.toLocal();
  return date == null
      ? 'Unavailable'
      : '${date.day}/${date.month}/${date.year}';
}

String _money(dynamic currency, dynamic price) {
  final n = num.tryParse('$price');
  final c = currency?.toString() ?? '';
  if (n == null) return [c, price?.toString() ?? ''].where((e) => e.isNotEmpty).join(' ');
  if (n == 0) return 'Free';
  var s = n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
  final parts = s.split('.');
  parts[0] = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  s = parts.join('.');
  return c.isEmpty ? s : '$c $s';
}

String _interval(dynamic value) {
  final s = value?.toString().toLowerCase() ?? '';
  switch (s) {
    case 'monthly':
    case 'month':
      return 'month';
    case 'yearly':
    case 'annual':
    case 'annually':
    case 'year':
      return 'year';
    case 'weekly':
    case 'week':
      return 'week';
    case 'daily':
    case 'day':
      return 'day';
    default:
      return s;
  }
}

class PlansAccessPage extends ConsumerWidget {
  const PlansAccessPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(subscriptionOverviewProvider);
    final workspace = ref.watch(workspaceProvider);
    final isCompany = workspace.activeCompanyId != null;
    final accent = isCompany ? _companyAccent : _personalAccent;
    final baseTheme = Theme.of(context);

    Future<void> refresh() async {
      ref.invalidate(subscriptionOverviewProvider);
      ref.invalidate(entitlementProvider);
      ref.invalidate(workspaceAccessSnapshotProvider);
      try {
        await ref.read(subscriptionOverviewProvider.future);
      } catch (_) {}
    }

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: accent),
      ),
      child: WorkspaceScaffold(
        company: isCompany,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leading: const AppBackButton(),
          title: const Text(
            'Plans & Access',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: refresh,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedRefresh,
                color: Colors.black87,
                size: 22,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: ColoredBox(
          color: _pageBackground,
          child: overview.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedWifiOff01,
                      color: Colors.black26,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Plan details are unavailable',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
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
              final requests = data['requests'] is Map
                  ? (data['requests'] as Map)['data']
                  : null;
              final pending = data['has_pending_request'] == true;
              final planName =
                  usage['plan_name']?.toString() ??
                  plan?['name']?.toString() ??
                  'No active plan';
              final plans = data['plans'] is List
                  ? (data['plans'] as List).whereType<Map>().toList()
                  : <Map>[];

              final usageKinds = <_UsageKind>[
                _UsageKind(
                  'records',
                  'Records',
                  HugeIcons.strokeRoundedDatabase,
                ),
                _UsageKind(
                  'storage',
                  'Media storage',
                  HugeIcons.strokeRoundedHardDrive,
                ),
                _UsageKind(
                  'exports',
                  'Monthly exports',
                  HugeIcons.strokeRoundedShare01,
                ),
              ];
              final usageTiles = <Widget>[
                for (final k in usageKinds)
                  if (usage[k.key] is Map)
                    _UsageTile(
                      icon: k.icon,
                      label: k.label,
                      data: Map<String, dynamic>.from(usage[k.key] as Map),
                    ),
              ];

              return RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    0,
                    16,
                    0,
                    32 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    _PlanHero(
                      workspaceLabel: workspace.label,
                      isCompany: isCompany,
                      planName: planName,
                      hasSubscription: subscription != null,
                      validUntil: subscription?['ends_at'] != null
                          ? _date(subscription!['ends_at'])
                          : null,
                      pending: pending,
                      onTap: plans.isEmpty
                          ? null
                          : () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const PlansCatalogPage(),
                              ),
                            ),
                    ),
                    if (pending) const _PendingBanner(),
                    if (usageTiles.isNotEmpty)
                      ProfileSection(
                        title: 'Workspace usage',
                        children: usageTiles,
                      ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: FeatureAccessSection(),
                    ),
                    if (requests is List && requests.isNotEmpty)
                      ProfileSection(
                        title: 'Recent requests',
                        children: [
                          for (final request in requests.whereType<Map>())
                            _RequestRow(request: request),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Hero ───────────────────────────────────────────────────────────

class _PlanHero extends StatelessWidget {
  const _PlanHero({
    required this.workspaceLabel,
    required this.isCompany,
    required this.planName,
    required this.hasSubscription,
    required this.validUntil,
    required this.pending,
    this.onTap,
  });

  final String workspaceLabel;
  final bool isCompany;
  final String planName;
  final bool hasSubscription;
  final String? validUntil;
  final bool pending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    final footer = !hasSubscription
        ? 'Pick a plan below to get started.'
        : validUntil != null
        ? 'Valid until $validUntil'
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.lerp(accent, Colors.white, 0.22)!],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Positioned(
                  right: -14,
                  top: -14,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedCrown,
                    color: Colors.white.withValues(alpha: 0.12),
                    size: 120,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isCompany
                                  ? Icons.business_outlined
                                  : Icons.person_outline_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                workspaceLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'CURRENT PLAN',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        planName,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                      if (footer != null || pending) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (footer != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedCalendar03,
                                    color: Colors.white.withValues(alpha: 0.85),
                                    size: 15,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    footer,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                            if (pending)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _amberSoft,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Pending approval',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _amber,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (onTap != null) ...[
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View plans & features',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(width: 6),
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedArrowRight01,
                                color: accent,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ],
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
class _PendingBanner extends StatelessWidget {
  const _PendingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _amberSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedClock01,
            color: _amber,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending approval',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _amber,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Your current access remains unchanged.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Usage ──────────────────────────────────────────────────────────

class _UsageKind {
  final String key;
  final String label;
  final dynamic icon;
  _UsageKind(this.key, this.label, this.icon);
}

class _UsageTile extends StatelessWidget {
  const _UsageTile({
    required this.icon,
    required this.label,
    required this.data,
  });
  final dynamic icon;
  final String label;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final divisor = label == 'Media storage' ? 1048576 : 1;
    final rawUsed = num.tryParse('${data['used']}');
    final rawLimit = num.tryParse('${data['limit']}');
    final used = rawUsed == null ? null : rawUsed / divisor;
    final limit = rawLimit == null || rawLimit == -1
        ? rawLimit
        : rawLimit / divisor;
    String number(num value) => value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    final suffix = divisor == 1 ? '' : ' MB';
    final text = limit == -1
        ? '${number(used ?? 0)}$suffix / Unlimited'
        : limit == null
        ? '${number(used ?? 0)}$suffix used · No configured limit'
        : '${number(used ?? 0)} / ${number(limit)}$suffix';
    final reached =
        rawLimit != null &&
        rawLimit >= 0 &&
        rawUsed != null &&
        rawUsed >= rawLimit;
    final warning =
        !reached &&
        rawLimit != null &&
        rawLimit > 0 &&
        rawUsed != null &&
        rawUsed / rawLimit >= .8;

    final scheme = Theme.of(context).colorScheme;
    final statusColor = reached
        ? scheme.error
        : warning
        ? const Color(0xFFE08A00)
        : scheme.primary;
    final hasBar = used != null && limit != null && limit > 0;
    final ratio = hasBar ? (used / limit).clamp(0, 1).toDouble() : 0.0;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: HugeIcon(icon: icon, color: statusColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasBar)
                Text(
                  '${(ratio * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
            ],
          ),
          if (hasBar) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                color: statusColor,
                backgroundColor: const Color(0xFFEEF1F4),
              ),
            ),
          ],
          if (reached || warning) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedAlert02,
                  color: statusColor,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  reached ? 'Allowance reached' : 'Approaching allowance',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Plans ──────────────────────────────────────────────────────────

class _PlanRequests extends ConsumerStatefulWidget {
  const _PlanRequests({
    required this.plans,
    required this.currentPlanId,
    required this.canRequest,
    required this.companyId,
    required this.onComplete,
  });
  final List<Map> plans;
  final dynamic currentPlanId;
  final bool canRequest;
  final int? companyId;
  final Future<void> Function() onComplete;

  @override
  ConsumerState<_PlanRequests> createState() => _PlanRequestsState();
}

class _PlanRequestsState extends ConsumerState<_PlanRequests> {
  bool busy = false;

  Future<void> request(Map plan) async {
    if (busy || !widget.canRequest) return;
    final session = ref.read(authSessionProvider);
    final company = widget.companyId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Request ${plan['name']}?'),
        content: const Text(
          'An administrator will review this request. Submitting it does not charge you or change your current access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit request'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        company != ref.read(workspaceProvider).activeCompanyId ||
        session.token != ref.read(authSessionProvider).token) {
      return;
    }
    setState(() => busy = true);
    try {
      final response = await ApiClient.postJson(
        '/billing/requests',
        bearerToken: session.token,
        body: {'subscription_plan_id': plan['id'], 'company_id': company},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = jsonDecode(response.body);
        throw Exception(
          body is Map
              ? body['message'] ?? 'Request failed.'
              : 'Request failed.',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan request submitted for approval.')),
      );
      await widget.onComplete();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit request: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _planCard(Map plan) {
    final accent = Theme.of(context).colorScheme.primary;
    final isCurrent =
        widget.currentPlanId != null &&
        plan['id']?.toString() == widget.currentPlanId.toString();
    final interval = _interval(plan['billing_interval']);
    final description = plan['description'];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? accent.withValues(alpha: 0.4) : _cardBorder,
          width: isCurrent ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${plan['name']}',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Current plan',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _money(plan['currency'], plan['price']),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                if (interval.isNotEmpty)
                  TextSpan(
                    text: '  / $interval',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
          if (description is String && description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Colors.black54,
              ),
            ),
          ],
          if (!isCurrent) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.canRequest && !busy
                    ? () => request(plan)
                    : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const HugeIcon(
                        icon: HugeIcons.strokeRoundedSent,
                        color: Colors.white,
                        size: 18,
                      ),
                label: const Text(
                  'Request plan',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 22, 24, 8),
        child: Text(
          'AVAILABLE PLANS',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Colors.black45,
          ),
        ),
      ),
      if (!widget.canRequest)
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Text(
            'Plan changes are unavailable right now.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
        ),
      for (final plan in widget.plans) _planCard(plan),
    ],
  );
}

// ── Requests ───────────────────────────────────────────────────────

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request});
  final Map request;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final name = request['plan'] is Map
        ? (request['plan']['name']?.toString() ?? 'Plan request')
        : 'Plan request';
    final status = request['status']?.toString() ?? 'Unknown';
    final created = request['created_at'];

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedTask01,
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (created != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _date(created),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _StatusChip(status: status),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    Color fg;
    Color bg;
    if (lower.contains('pending')) {
      fg = _amber;
      bg = _amberSoft;
    } else if (lower.contains('approv') ||
        lower.contains('active') ||
        lower.contains('complete')) {
      fg = _green;
      bg = _greenSoft;
    } else if (lower.contains('reject') ||
        lower.contains('declin') ||
        lower.contains('cancel')) {
      fg = Theme.of(context).colorScheme.error;
      bg = fg.withValues(alpha: 0.10);
    } else {
      fg = Colors.black54;
      bg = const Color(0xFFF1F3F5);
    }
    final label = status.isEmpty
        ? status
        : status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}