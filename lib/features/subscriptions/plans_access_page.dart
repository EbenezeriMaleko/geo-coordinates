import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../workspaces/workspace_provider.dart';
import 'subscription_provider.dart';
import '../workspaces/workspace_page_style.dart';
import 'feature_access_section.dart';
import 'entitlement_provider.dart';
import 'dart:convert';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';

class PlansAccessPage extends ConsumerWidget {
  const PlansAccessPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(subscriptionOverviewProvider);
    final workspace = ref.watch(workspaceProvider);
    final theme = Theme.of(context);
    Future<void> refresh() async {
      ref.invalidate(subscriptionOverviewProvider);
      ref.invalidate(entitlementProvider);
      ref.invalidate(workspaceAccessSnapshotProvider);
      try {
        await ref.read(subscriptionOverviewProvider.future);
      } catch (_) {}
    }

    return WorkspaceScaffold(
      company: workspace.activeCompanyId != null,
      appBar: AppBar(
        title: const Text('Plans & Access'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 32),
                const SizedBox(height: 12),
                const Text(
                  'Plan details are unavailable',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Check your connection and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
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
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Icon(
                  workspace.activeCompanyId == null
                      ? Icons.person_outline_rounded
                      : Icons.business_outlined,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  workspace.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  usage['plan_name']?.toString() ??
                      plan?['name']?.toString() ??
                      'No active plan',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subscription?['ends_at'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Valid until ${_date(subscription!['ends_at'])}',
                    ),
                  ),
                if (data['has_pending_request'] == true)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.schedule_outlined),
                      title: Text('Pending approval'),
                      subtitle: Text('Your current access remains unchanged.'),
                    ),
                  ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Text('Workspace usage', style: theme.textTheme.titleMedium),
                for (final entry in const {
                  'records': 'Records',
                  'storage': 'Media storage',
                  'exports': 'Monthly exports',
                }.entries)
                  if (usage[entry.key] is Map)
                    _UsageRow(
                      label: entry.value,
                      data: Map<String, dynamic>.from(usage[entry.key] as Map),
                    ),
                const FeatureAccessSection(),
                if (data['plans'] is List)
                  _PlanRequests(
                    plans: (data['plans'] as List).whereType<Map>().toList(),
                    canRequest:
                        data['can_request'] == true &&
                        data['has_pending_request'] != true,
                    companyId: workspace.activeCompanyId,
                    onComplete: refresh,
                  ),
                if (requests is List && requests.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Recent requests', style: theme.textTheme.titleMedium),
                  for (final request in requests.whereType<Map>())
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        request['plan'] is Map
                            ? (request['plan']['name']?.toString() ??
                                  'Plan request')
                            : 'Plan request',
                      ),
                      subtitle: Text(
                        request['status']?.toString() ?? 'Unknown',
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  static String _date(dynamic value) {
    final date = DateTime.tryParse(value.toString())?.toLocal();
    return date == null
        ? 'Unavailable'
        : '${date.day}/${date.month}/${date.year}';
  }
}

class _PlanRequests extends ConsumerStatefulWidget {
  const _PlanRequests({
    required this.plans,
    required this.canRequest,
    required this.companyId,
    required this.onComplete,
  });
  final List<Map> plans;
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

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 24),
      Text('Available plans', style: Theme.of(context).textTheme.titleMedium),
      for (final plan in widget.plans)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${plan['name']}'),
          subtitle: Text(
            '${plan['currency'] ?? ''} ${plan['price'] ?? ''} · ${plan['billing_interval'] ?? ''}',
          ),
          trailing: IconButton(
            tooltip: 'Request plan',
            icon: const Icon(Icons.send_outlined),
            onPressed: widget.canRequest && !busy ? () => request(plan) : null,
          ),
        ),
    ],
  );
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.label, required this.data});
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
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              Text(text, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (used != null && limit != null && limit > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (used / limit).clamp(0, 1).toDouble(),
                minHeight: 5,
                color: reached
                    ? colors.error
                    : warning
                    ? colors.tertiary
                    : colors.primary,
              ),
            ),
          ],
          if (reached || warning)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                reached ? 'Allowance reached' : 'Approaching allowance',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: reached ? colors.error : colors.tertiary,
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
