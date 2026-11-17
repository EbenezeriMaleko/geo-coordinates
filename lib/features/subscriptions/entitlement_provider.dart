import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../workspaces/workspace_provider.dart';
import 'plans_access_page.dart';
import 'access_navigation.dart';

class FeatureDecision {
  const FeatureDecision({
    required this.allowed,
    required this.name,
    this.reason,
  });
  final bool allowed;
  final String name;
  final String? reason;
  factory FeatureDecision.fromJson(Map json) => FeatureDecision(
    allowed: json['allowed'] == true,
    name: json['display_name']?.toString() ?? 'Feature',
    reason: json['reason']?.toString(),
  );
}

final workspaceAccessSnapshotProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      var disposed = false;
      Timer? refreshTimer;
      // Register before awaiting: an obsolete request may finish after disposal.
      ref.onDispose(() {
        disposed = true;
        refreshTimer?.cancel();
      });
      final session = ref.watch(authSessionProvider);
      final workspace = ref.watch(workspaceProvider);
      final signedIn = session.isLoggedIn && session.isVerified;
      if (signedIn && workspace.isLoading) {
        throw Exception('Workspace access is loading.');
      }
      final response = await ApiClient.getJson(
        signedIn ? '/entitlements' : '/feature-policies',
        bearerToken: signedIn ? session.token : null,
        queryParameters: signedIn && workspace.activeCompanyId != null
            ? {'company_id': workspace.activeCompanyId}
            : null,
        tag: 'feature_access',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Unable to verify feature access.');
      }
      final json = jsonDecode(response.body);
      final features = json is Map && json['data'] is Map
          ? json['data']['features']
          : null;
      if (features is! List) {
        throw Exception('Invalid feature access response.');
      }
      final expiry = DateTime.tryParse(
        json['data']['cache_expires_at']?.toString() ?? '',
      );
      final remaining =
          expiry?.difference(DateTime.now()) ?? const Duration(minutes: 1);
      final duration = remaining <= Duration.zero
          ? const Duration(seconds: 1)
          : remaining > const Duration(minutes: 1)
          ? const Duration(minutes: 1)
          : remaining;
      if (!disposed) {
        refreshTimer = Timer(duration, () {
          if (!disposed) ref.invalidateSelf();
        });
      }
      return Map<String, dynamic>.from(json['data'] as Map);
    });

final entitlementProvider =
    FutureProvider.autoDispose<Map<String, FeatureDecision>>((ref) async {
      final data = await ref.watch(workspaceAccessSnapshotProvider.future);
      return {
        for (final item in (data['features'] as List).whereType<Map>())
          if (item['key'] is String)
            item['key'] as String: FeatureDecision.fromJson(item),
      };
    });

Map<String, bool> parseWorkspacePermissions(dynamic raw) => raw is Map
    ? {
        for (final entry in raw.entries)
          if (entry.key is String) entry.key as String: entry.value == true,
      }
    : {};

final workspacePermissionsProvider =
    FutureProvider.autoDispose<Map<String, bool>>((ref) async {
      final data = await ref.watch(workspaceAccessSnapshotProvider.future);
      return parseWorkspacePermissions(data['workspace_permissions']);
    });

Future<bool> checkFeatureAccess(
  BuildContext context,
  WidgetRef ref,
  String key, {
  bool openPlansOnDenied = true,
}) async {
  final company = ref.read(workspaceProvider).activeCompanyId;
  final token = ref.read(authSessionProvider).token;
  ref.invalidate(entitlementProvider);
  ref.invalidate(workspaceAccessSnapshotProvider);
  Map<String, FeatureDecision> features;
  try {
    features = await ref.read(entitlementProvider.future);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to verify access. Check your connection and try again.',
          ),
        ),
      );
    }
    return false;
  }
  if (!context.mounted ||
      company != ref.read(workspaceProvider).activeCompanyId ||
      token != ref.read(authSessionProvider).token) {
    return false;
  }
  final decision = features[key];
  if (decision?.allowed == true) return true;
  final session = ref.read(authSessionProvider);
  if (!session.isLoggedIn || openPlansOnDenied) {
    await openAccessRequirement(context, session);
    return false;
  }
  if (decision == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This feature is not configured on the server yet.'),
      ),
    );
    return false;
  }
  final unavailable = [
    'feature_unavailable',
    'feature_not_configured',
    'unknown_feature',
  ].contains(decision.reason);
  final roleDenied = decision.reason == 'company_role_forbidden';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded),
      title: Text(
        roleDenied
            ? 'Company role restriction'
            : unavailable
            ? 'Feature unavailable'
            : 'Plan access required',
      ),
      content: Text(
        roleDenied
            ? 'Your company role does not allow this action. Contact a company administrator.'
            : unavailable
            ? '${decision.name} is not available on this server yet.'
            : '${decision.name} is not included in the access available to this workspace.',
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!unavailable &&
                !roleDenied &&
                ref.read(authSessionProvider).isVerified)
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PlansAccessPage(),
                    ),
                  );
                },
                child: const Text('View plan access'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Maybe Later'),
            ),
          ],
        ),
      ],
    ),
  );
  return false;
}
