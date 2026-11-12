import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'entitlement_provider.dart';

class FeatureAccessSection extends ConsumerWidget {
  const FeatureAccessSection({super.key});

  static String status(FeatureDecision decision) {
    if (decision.allowed) return 'Available';
    return switch (decision.reason) {
      'company_role_forbidden' => 'Restricted by company role',
      'feature_unavailable' ||
      'feature_not_configured' ||
      'unknown_feature' => 'Not available yet',
      'company_workspace_required' => 'Company workspace required',
      'company_subscription_expired' => 'Company plan ended',
      'company_membership_inactive' => 'Company access inactive',
      _ => 'Plan access required',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(entitlementProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Feature access', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        access.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Checking workspace access...')),
              ],
            ),
          ),
          error: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Access could not be verified. This does not mean your features are locked.',
              ),
              TextButton.icon(
                onPressed: () { ref.invalidate(workspaceAccessSnapshotProvider); ref.invalidate(entitlementProvider); },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry access check'),
              ),
            ],
          ),
          data: (features) {
            if (features.isEmpty) {
              return const Text('No feature policies are configured yet.');
            }
            final entries = features.entries.toList()
              ..sort((a, b) => a.value.name.compareTo(b.value.name));
            return Column(
              children: entries.map((entry) {
                final decision = entry.value;
                final label = status(decision);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: Icon(
                    decision.allowed
                        ? Icons.check_circle_outline_rounded
                        : Icons.lock_outline_rounded,
                    size: 21,
                    color: decision.allowed
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    decision.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(decision.name),
                      content: Text(
                        decision.allowed
                            ? 'This feature is available to the selected workspace. Availability here does not mean the tool is implemented on every device.'
                            : '$label. Access is evaluated for the selected workspace; your saved records are retained.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
