import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/models/auth_models.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/account_page.dart';
import '../../auth/ui/device_sessions_page.dart';
import '../../../core/localization/app_localizations.dart';
import '../../notifications/ui/notifications_page.dart';
import '../../subscriptions/plans_access_page.dart';
import '../../workspaces/company_create_page.dart';
import '../../workspaces/company_invitations_page.dart';
import '../../workspaces/company_members_page.dart';
import '../../workspaces/field_jobs_page.dart';
import '../../workspaces/organization_page.dart';
import '../../workspaces/workspace_provider.dart';
import '../../widget/settings_widget.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  static const Color _teal = Color(0xFF197568);

  void _push(Widget page) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final workspace = ref.watch(workspaceProvider);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final verified = session.isLoggedIn && session.isVerified;

    return ColoredBox(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _ProfileHeader(session: session, onTap: () => _push(const AccountPage())),
          const SettingsDivider(),

          // ── Account ──────────────────────────────────────────
          SettingsSectionHeader(l10n.t('Account')),
          SettingsItem(
            title: l10n.t('Account'),
            subtitle: session.isLoggedIn
                ? 'Manage your profile and sign-in details'
                : l10n.t('Sign in only when you want to sync data to the server.'),
            onTap: () => _push(const AccountPage()),
          ),
          if (session.isLoggedIn)
            SettingsItem(
              title: 'Signed-in devices',
              subtitle: 'Review sessions and sign out other devices',
              onTap: () => _push(const DeviceSessionsPage()),
            ),
          if (verified)
            SettingsItem(
              title: 'Notifications',
              subtitle: 'View announcements and manage mobile alerts',
              onTap: () => _push(const NotificationsPage()),
            ),
          if (verified)
            SettingsItem(
              title: 'Plans & Access',
              subtitle: 'Current plan, usage and approval status',
              onTap: () => _push(const PlansAccessPage()),
            ),
          const SettingsDivider(),

          // ── Workspace (only when verified) ───────────────────
          if (verified) ...[
            SettingsSectionHeader(l10n.t('Workspace')),
            SettingsItem(
              title: l10n.t('Workspace'),
              subtitle: workspace.label,
              onTap: _showWorkspaceSelector,
            ),
            SettingsItem(
              title: 'Company invitations',
              subtitle: 'Review invitations to join a company',
              onTap: () => _push(const CompanyInvitationsPage()),
            ),
            SettingsItem(
              title: 'Create company',
              subtitle: 'Create a company workspace you own',
              onTap: _createCompany,
            ),
            const SettingsDivider(),
          ],

          // ── Active company ───────────────────────────────────
          if (verified && workspace.activeCompanyId != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.business_outlined, color: _teal, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workspace.activeCompany?.name ?? 'Company workspace',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _teal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Company workspace',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (canViewCompanyDirectory(workspace, session.user?.role))
              SettingsItem(
                title: 'Company members',
                subtitle: 'Members and pending invitations',
                onTap: () => _push(const CompanyMembersPage()),
              ),
            SettingsItem(
              title: 'Projects & Teams',
              subtitle: 'Company projects and team members',
              onTap: () => _push(const OrganizationPage()),
            ),
            SettingsItem(
              title: 'Field jobs',
              subtitle: 'Company assignments and progress',
              onTap: () => _push(const FieldJobsPage()),
            ),
          ],
        ],
      ),
    );
  }

  // ── MOVE THESE TWO METHODS HERE from settings_page.dart, unchanged: ──
  //   Future<void> _createCompany() async { ... }
  //   Future<void> _showWorkspaceSelector() async { ... }
  //   Widget _workspaceOption({...}) { ... }
  // (They only use ref, context, mounted, workspaceProvider, authSessionProvider,
  //  CompanyCreatePage and companyRoleLabel, which are all imported above.)

  Future<void> _createCompany() async {
    final token = ref.read(authSessionProvider).token;
    final company = await Navigator.of(context).push<CompanyWorkspace>(
      MaterialPageRoute(builder: (_) => const CompanyCreatePage()),
    );
    if (!mounted ||
        company == null ||
        token != ref.read(authSessionProvider).token) {
      return;
    }
    final error = ref.read(workspaceProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? 'Company created. Select it from Workspace when ready.'
              : 'Company created. Refresh your workspace list to see it.',
        ),
      ),
    );
  }

  Widget _workspaceOption({
    required BuildContext context,
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.1)
              : const Color(0xFFF1F4F7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          title == context.l10n.t('Personal workspace')
              ? Icons.person_outline_rounded
              : Icons.business_outlined,
          color: selected ? primary : const Color(0xFF526579),
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: primary)
          : null,
      onTap: onTap,
    );
  }

  Future<void> _showWorkspaceSelector() async {
    ref.read(workspaceProvider.notifier).refresh();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final workspace = ref.watch(workspaceProvider);
          final theme = Theme.of(context);
          return SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.72,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD5DCE5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.t('Choose workspace'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.t('Refresh'),
                          onPressed: workspace.isLoading
                              ? null
                              : () => ref
                                    .read(workspaceProvider.notifier)
                                    .refresh(),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                    child: Text(
                      context.l10n.t(
                        'Personal records and each company workspace stay separate.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (workspace.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  if (workspace.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_outlined, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Unable to refresh workspaces. Your current selection is unchanged.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!workspace.isLoading)
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          _workspaceOption(
                            context: context,
                            selected: workspace.activeCompanyId == null,
                            title: context.l10n.t('Personal workspace'),
                            subtitle: context.l10n.t('Your individual records'),
                            onTap: () async {
                              await ref
                                  .read(workspaceProvider.notifier)
                                  .selectCompany(null);
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                            },
                          ),
                          ...workspace.companies.map(
                            (company) => _workspaceOption(
                              context: context,
                              selected: workspace.activeCompanyId == company.id,
                              title: company.name,
                              subtitle: companyRoleLabel(company.role),
                              onTap: () async {
                                await ref
                                    .read(workspaceProvider.notifier)
                                    .selectCompany(company.id);
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                            ),
                          ),
                          if (workspace.companies.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              child: Text(
                                context.l10n.t(
                                  'No company workspace is available for this account.',
                                ),
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final AuthSession session;
  final VoidCallback onTap;
  const _ProfileHeader({required this.session, required this.onTap});

  String _initials(String name, String email) {
    final source = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return source[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final user = session.user;
    final name = user?.name.trim() ?? '';
    final email = user?.email.trim() ?? '';
    final signedIn = session.isLoggedIn;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: primary.withValues(alpha: 0.12),
              child: signedIn
                  ? Text(
                      _initials(name, email),
                      style: TextStyle(
                        color: primary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Icon(Icons.person_outline, color: primary, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    signedIn
                        ? (name.isNotEmpty ? name : email)
                        : 'Not signed in',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    signedIn
                        ? (name.isNotEmpty ? email : 'Signed in')
                        : 'Tap to sign in and sync your data',
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}