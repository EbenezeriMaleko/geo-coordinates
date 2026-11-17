import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../subscriptions/entitlement_provider.dart';
import '../subscriptions/access_navigation.dart';
import '../auth/providers/auth_provider.dart';

void openPlansAccess(BuildContext context) {
  final session = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(authSessionProvider);
  openAccessRequirement(context, session);
}

/// Keeps a restricted action visible and routes taps to workspace access.
/// Busy states, missing inputs, and network failures must not be passed as locks.
class PlanAccessLock extends ConsumerWidget {
  const PlanAccessLock({super.key, required this.locked, required this.child});
  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!locked) return child;
    final signedIn = ref.watch(authSessionProvider).isLoggedIn;
    return Semantics(
      button: true,
      label: signedIn ? 'Locked. View Plans & Access' : 'Sign in required',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openPlansAccess(context),
        child: Stack(
          children: [
            ExcludeSemantics(
              child: ExcludeFocus(child: IgnorePointer(child: child)),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                ),
                child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedLockKey,
                  size: 16,
                  color: Color(0xFF001F3F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Only explicit server denials lock a feature; unknown access stays unknown.
class FeatureAccessLock extends ConsumerWidget {
  const FeatureAccessLock({
    super.key,
    required this.features,
    required this.child,
    this.allDenied = false,
  });
  final bool allDenied;
  final List<String> features;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decisions = ref.watch(entitlementProvider).asData?.value;
    return PlanAccessLock(
      locked: allDenied
          ? features.every((key) => decisions?[key]?.allowed == false)
          : features.any((key) => decisions?[key]?.allowed == false),
      child: child,
    );
  }
}
